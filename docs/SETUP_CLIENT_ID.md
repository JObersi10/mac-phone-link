# Supplying a client id

This client ships **no** OAuth client id. To sign in, you supply one that **you
are authorized to use** — your own Microsoft Entra / MSA app registration. The
app reads it at runtime; it is never compiled into the binary or committed here.

> **Clean-room / ToS note.** This project does not embed Microsoft's first-party
> Phone Link client id and does not include any tool to extract one. Interop is
> matching the protocol with *your own* identity; presenting Microsoft's
> first-party id would be impersonating their app, which this repo does not do
> or facilitate. What you run on your own account is your responsibility.

## How to supply it

Resolution order (first match wins), via `ClientIdResolver`:

1. **Explicit** — pass it in code (`DeviceCodeConfig(clientId:)`).
2. **Environment variable** — `PHONELINK_CLIENT_ID`:
   ```bash
   export PHONELINK_CLIENT_ID="<your-app-client-id>"
   ```
3. **Config file** — first line of `~/.config/phonelink/client_id`:
   ```bash
   mkdir -p ~/.config/phonelink
   printf '%s\n' "<your-app-client-id>" > ~/.config/phonelink/client_id
   ```

If none is set, auth stays unconfigured — nothing is assumed or embedded.

## Getting your own client id

Register an application in the Microsoft Entra admin center (consumers / personal
Microsoft accounts), add a redirect for the device-code / public-client flow, and
use that registration's **Application (client) ID**. Whether a given resource
(e.g. DCG) will issue tokens to a non-first-party registration is between you and
Microsoft's service — see `docs/FINDINGS.md` for what we observed.
