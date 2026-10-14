# Security

Privileged helpers must verify payload signatures, pin user-owned session directories, reject symbolic links, and restore temporary diagnostics after ordinary session termination. Do not weaken these checks to make installation pass.

Building and testing do not grant macOS permissions. Driver installation and audio capture are separate, visible actions requiring human approval. Bluetooth diagnostics can include other devices' traffic. Abrupt power loss or forced termination may prevent normal cleanup; inspect system state before resuming a failed session.

Persistent voice approval is an explicit opt-in, separate from the old single-session consent. It installs an on-demand, root-owned helper without starting capture. XPC peers require both the expected identifier and the current signing certificate. Callers cannot choose a command, path, UID or PID; the daemon derives identity from the connection, permits one active session and only lets its owning connection stop it. Connection loss requests normal capture shutdown. Removing approval requires an administrator and retains the virtual microphone and user mappings. Never transfer local signing keys into the public repository.

Report vulnerabilities privately via the in-app developer contact or the formal repository's maintainer contact. Do not post recordings, administrator passwords or raw Bluetooth logs in public issues. A local development signature is not a notarized production identity.

Public beta installers exclude Apple binaries. Runtime imports accept only the expected components with Apple's code identifiers and signature anchor; copied content is verified again before use. Neither importing nor packaging starts capture. Public betas are self-signed and unnotarized; verify the release origin and SHA256, and use macOS's visible approval controls rather than disabling Gatekeeper. A disposable CI signing identity cannot preserve privacy approval across separately built beta releases.
