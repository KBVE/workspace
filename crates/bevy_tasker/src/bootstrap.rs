//! Starting the web workers that back [`crate::spawn`] on WASM+atomics.
//!
//! The pool cannot be started from JavaScript, because by the time the page's
//! `await init()` resolves the game is already gone: Bevy's `App::run` never
//! returns on the web -- wasm-bindgen unwinds it by throwing -- so any code
//! after the init call is unreachable. The workers therefore have to be
//! spawned from Rust, from `main`, before the app starts.
//!
//! Each worker instantiates the same module against the same shared memory and
//! calls [`crate::worker_entry_point`], which parks it on the shared queue.
//! Nothing here is Bevy-specific; it is the wasm-bindgen half of a thread pool.

use wasm_bindgen::JsValue;
use wasm_bindgen::prelude::*;

#[wasm_bindgen(inline_js = r#"
    export function bevy_tasker_spawn_worker(worker_url, bundle_url, module, memory) {
        // `type: 'module'` so the worker can `import()` the wasm-bindgen glue,
        // which is an ES module. Classic workers cannot.
        const worker = new Worker(worker_url, { type: 'module' });
        // The module and the memory are both structured-cloneable, and cloning
        // a WebAssembly.Memory backed by a SharedArrayBuffer shares it rather
        // than copying -- that sharing is the whole mechanism.
        worker.postMessage({ bundle: bundle_url, module, memory });
        return worker;
    }

    export function bevy_tasker_hardware_concurrency() {
        return navigator.hardwareConcurrency || 4;
    }

    export function bevy_tasker_is_worker() {
        return typeof WorkerGlobalScope !== 'undefined'
            && self instanceof WorkerGlobalScope;
    }
"#)]
extern "C" {
    fn bevy_tasker_spawn_worker(
        worker_url: &str,
        bundle_url: &str,
        module: JsValue,
        memory: JsValue,
    ) -> JsValue;

    fn bevy_tasker_hardware_concurrency() -> usize;

    fn bevy_tasker_is_worker() -> bool;
}

/// Whether this thread is a web worker rather than the page's main thread.
///
/// Needed because every thread instantiates the same module, and wasm-bindgen
/// runs the module's start section -- which for a binary crate is `main` -- on
/// each instantiation. Without a guard at the top of `main`, every worker
/// would build and run its own copy of the application. So:
///
/// ```rust,ignore
/// fn main() {
///     if bevy_tasker::is_worker() {
///         return; // the worker script calls worker_entry_point next
///     }
///     bevy_tasker::start_workers("./worker.js", "./bundle.js", None);
///     App::new().run();
/// }
/// ```
///
/// The test is for `WorkerGlobalScope` rather than for the absence of `window`,
/// because that also answers "yes" in Node and in any other host without a DOM,
/// where the right answer is "no".
pub fn is_worker() -> bool {
    bevy_tasker_is_worker()
}

/// How many workers [`start_workers`] starts when given no count.
///
/// One per logical core minus the one the main thread is already using. The
/// main thread is not a spare: on the web it owns the canvas, the event loop
/// and every `wgpu` handle, and it is busy for most of every frame.
pub fn default_worker_count() -> usize {
    bevy_tasker_hardware_concurrency().saturating_sub(1).max(1)
}

/// Starts the worker pool.
///
/// `worker_url` is the script each worker runs, resolved against the page --
/// `"./worker.js"` for a flat bundle directory. `bundle_url` is the
/// wasm-bindgen glue that worker script imports; it is passed rather than
/// guessed because a project may ship several bundles from one directory (a
/// WebGPU one and a WebGL2 one, say) and a worker has to instantiate the same
/// one the main thread did.
///
/// Call before `App::run`. Returns the number of workers asked for; a worker
/// that fails to start reports on the console rather than here, since
/// `new Worker` is asynchronous past the constructor.
pub fn start_workers(worker_url: &str, bundle_url: &str, count: Option<usize>) -> usize {
    let count = count.unwrap_or_else(default_worker_count);

    // `wasm_bindgen::module()` is the compiled module this instance came from,
    // so workers instantiate exactly the binary that is already running rather
    // than re-fetching and re-compiling it.
    let module = wasm_bindgen::module();
    let memory = wasm_bindgen::memory();

    for _ in 0..count {
        // Deliberately dropped: a worker parks itself on the shared queue and
        // lives as long as the page. Keeping the handles would mean owning a
        // shutdown path for something that has no shutdown.
        let _ = bevy_tasker_spawn_worker(worker_url, bundle_url, module.clone(), memory.clone());
    }

    count
}
