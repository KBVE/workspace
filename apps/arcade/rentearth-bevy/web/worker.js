// One pool thread.
//
// The main thread posts the compiled module and the shared memory, and this
// instantiates that same module against that same memory -- which is what
// makes it a thread of the running program rather than a second copy of it.
// Nothing is re-fetched; there is one wasm download for the whole page.
//
// `main` runs here too: wasm-bindgen's start section calls it on every
// instantiation. It returns immediately because bevy_tasker::is_worker() is
// true, and then worker_entry_point parks this thread on the shared queue.
self.onmessage = async (event) => {
  const { bundle, module, memory } = event.data;

  try {
    const glue = await import(bundle);
    await glue.default({ module_or_path: module, memory });
    glue.worker_entry_point();
  } catch (error) {
    // A worker that dies silently looks like a worker that is merely idle, and
    // the symptom downstream is a task that never resolves. Say so.
    console.error('rentearth: worker failed to start', error);
  }
};
