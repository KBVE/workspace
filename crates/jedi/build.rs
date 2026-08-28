use std::fs;
use std::path::Path;

/// Where the schemas live, relative to this crate.
///
/// Nothing is here yet. The schemas are still in the Nx workspace at
/// KBVE/kbve packages/data/proto, and moving them is its own migration: this
/// repository already has a buf-managed tree under packages/protobuf with a
/// different layout, so the two have to be reconciled rather than copied.
///
/// Until then the generated code in src/proto is what compiles, which is why
/// regeneration is opt-in rather than the default.
const PROTO_ROOT: &str = "../../packages/protobuf/jedi";

fn main() {
    // Regeneration is opt-in: the generated tree under src/proto is committed,
    // so an ordinary build needs neither protoc nor the schemas.
    if std::env::var("BUILD_PROTO").is_err() {
        return;
    }

    // Without this the compile fails inside prost with a path error that reads
    // as a protoc problem rather than a missing migration.
    if !Path::new(PROTO_ROOT).exists() {
        panic!(
            "BUILD_PROTO is set but {PROTO_ROOT} does not exist.\n\
             jedi's schemas have not been migrated from KBVE/kbve \
             packages/data/proto yet, so the committed src/proto is the only \
             source of the generated code. Unset BUILD_PROTO to build from it."
        );
    }

    println!("[JEDI] Building the protobufs.");
    let out_dir = "src/proto";

    fs::create_dir_all(out_dir).unwrap();

    tonic_prost_build::configure()
        .build_client(true)
        .build_server(true)
        .out_dir(out_dir)
        // Redis
        .type_attribute(
            "redis.RedisCommand",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.RedisCommand.command",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.SetCommand",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.GetCommand",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.DelCommand",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.RedisResponse",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.RedisEvent",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.RedisEventObject",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.RedisEventObject.object",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.WatchCommand",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.UnwatchCommand",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.RedisKeyUpdate",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.RedisKeyUpdate.state",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.RedisWsMessage",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.RedisWsMessage.message",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.Ping",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.Pong",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.ErrorMessage",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        // Redis Stream Types
        .type_attribute(
            "redis.RedisStream",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.RedisStream.payload",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.XAddPayload",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.XReadPayload",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.XReadResponse",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.StreamReadRequest",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.StreamMessages",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.StreamEntry",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "redis.Field",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        // Groq
        .type_attribute(
            "groq.GroqMessage",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "groq.GroqMessageContent",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "groq.GroqChoice",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "groq.GroqUsage",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .bytes(".jedi")
        // Jedi
        .type_attribute(
            "jedi.MessageKind",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "jedi.PayloadFormat",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "jedi.JediEnvelope",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "jedi.FlexEnvelope",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "jedi.FlagEnvelope",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "jedi.RawEnvelope",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "jedi.JediMessage",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "jedi.JediMessage.envelope",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        // Twitch
        .type_attribute(
            "twitch.TwitchEventObject",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "twitch.TwitchChatMessage",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "twitch.TwitchJoinEvent",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "twitch.TwitchPartEvent",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "twitch.TwitchNoticeEvent",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "twitch.TwitchModerationEvent",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "twitch.TwitchSubEvent",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "twitch.TwitchRaidEvent",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "twitch.TwitchCheerEvent",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "twitch.TwitchRedemptionEvent",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "twitch.TwitchPing",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "twitch.TwitchPong",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "twitch.TwitchSender",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "twitch.TwitchEventObject.object",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        // ClickHouse
        .type_attribute(
            "clickhouse.SeverityLevel",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "clickhouse.KeyValue",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "clickhouse.TimeRange",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "clickhouse.Pagination",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "clickhouse.LogEntry",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "clickhouse.LogQueryRequest",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "clickhouse.LogQueryResponse",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "clickhouse.LogStatsRequest",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "clickhouse.LogStatsBucket",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "clickhouse.LogStatsResponse",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "clickhouse.RawQueryRequest",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "clickhouse.RawQueryResponse",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "clickhouse.InsertRequest",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "clickhouse.InsertResponse",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "clickhouse.DdlRequest",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "clickhouse.DdlResponse",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "clickhouse.TailRequest",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        // GitHub
        .type_attribute(
            "github.GitHubUser",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.GitHubLabel",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.GitHubIssueType",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.GitHubIssue",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.CreateIssueRequest",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.UpdateIssueRequest",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.GitHubRef",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.GitHubPull",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.MergePullRequest",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.GitHubMergeResult",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.GitHubCommitAuthor",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.GitHubCommitDetail",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.GitHubCommit",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.GitHubRepo",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.GitHubStatusChecks",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.GitHubEnforceAdmins",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.GitHubBranchProtection",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.GitHubComment",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.GitHubSearchResult",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.GitHubWorkflow",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.GitHubWorkflowsResponse",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.DispatchWorkflowRequest",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "github.GitHubRateLimit",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        // Shared git-forge primitives (explicit so the `.git` prefix can't also
        // catch the `github` package) + a whole-package matcher for Forgejo.
        .type_attribute(
            "git.GitForge",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "git.GitVisibility",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "git.GitActor",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            "git.GitCommitAuthor",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        .type_attribute(
            ".forgejo",
            "#[derive(serde::Serialize, serde::Deserialize)]",
        )
        // .type_attribute(".", "#[derive(serde::Serialize, serde::Deserialize)]")
        // .field_attribute("status.StatusMessage.type", "#[bitflags]")
        .compile_protos(
            &[
                format!("{PROTO_ROOT}/jedi/redis.proto"),
                format!("{PROTO_ROOT}/jedi/groq.proto"),
                format!("{PROTO_ROOT}/jedi/jedi.proto"),
                format!("{PROTO_ROOT}/jedi/twitch.proto"),
                format!("{PROTO_ROOT}/jedi/clickhouse.proto"),
                format!("{PROTO_ROOT}/git/github.proto"),
                format!("{PROTO_ROOT}/git/git_common.proto"),
                format!("{PROTO_ROOT}/git/forgejo.proto"),
                format!("{PROTO_ROOT}/kbve/staff.proto"),
            ],
            &[format!("{PROTO_ROOT}/jedi"), PROTO_ROOT.to_string()],
        )
        .expect("Failed to compile Protobuf files");
}
