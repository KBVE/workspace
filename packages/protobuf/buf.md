# buf.build/kbve/proto

Canonical Protocol Buffer schemas for the KBVE ecosystem.

## Layers

| Package | Contents | May import |
| --- | --- | --- |
| `kbve.type.v1` | identifiers and primitive wrappers | well-known types only |
| `kbve.common.v1` | shared messages and enums | `kbve.type.v1` |
| `kbve.dialogue.v1` | shared domain: conversation graphs | `type`, `common` |
| `kbve.<domain>.v1` | domain schemas | `type`, `common`, shared domains |

Imports form a one-way graph with no cycles. A domain never imports a peer
domain. When two peers need the same thing it moves down: into `common` if it
is a plain type, or into a shared domain if it carries real modelling of its
own.

## Conventions

- Every package carries a version suffix. Breaking changes ship as `v2`
  alongside `v1`.
- Identifiers use `kbve.type.v1.Ulid` / `Uuid`, never a bare `string id`.
- Timestamps use `google.protobuf.Timestamp`.
- Removed fields are `reserved`, both number and name.
- Content registries embed `kbve.common.v1.RegistryMeta` as field 1.
