"""Generated protobuf and gRPC stubs for kbve.

Vendored, and deliberately so for now. These files were generated in the Nx
workspace from packages/data/proto/kbve/kbve.proto -- 33 lines declaring
``package kbve`` with ``service Health { Check }`` and ``service Echo { Ping }``
-- and that .proto did not come across. So this is gencode with no schema in
this repository: it cannot be regenerated, linted, or checked for breakage, and
its own header says NO CHECKED-IN PROTOBUF GENCODE.

The end state is packages/protobuf, which owns every wire type in the workspace,
gitignores gen/ and rebuilds it with `buf generate`. Folding these in is waiting
on that migration rather than racing it, and needs two things when it happens:

- a grpc-python plugin in buf.gen.yaml. It currently runs
  protocolbuffers/python, which emits messages and no service stubs, so nothing
  in the workspace produces the _pb2_grpc module kbve.server.services imports.
- a decision about the package name. The repository convention is
  kbve/<domain>/v1, which would move the RPC path from /kbve.Health/Check to
  /kbve.health.v1.Health/Check.
"""
