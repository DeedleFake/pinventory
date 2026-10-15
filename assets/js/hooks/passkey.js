import {
  reviveCreationOptions,
  reviveRequestOptions,
  serializeAssertion,
  serializeAttestation,
} from "./passkey_codec"

// Runs WebAuthn ceremonies for the LiveView. The server pushes options;
// the hook calls navigator.credentials and pushes the result back.
const Passkey = {
  mounted() {
    if (!window.PublicKeyCredential) {
      this.el.dataset.passkeyUnsupported = ""
      this.pushEvent("passkey_unsupported", {})
      return
    }

    this.handleEvent("passkey:register", async ({options}) => {
      try {
        const cred = await navigator.credentials.create({publicKey: reviveCreationOptions(options)})
        this.pushEvent("passkey_attestation", {credential: serializeAttestation(cred)})
      } catch (e) {
        this.pushEvent("passkey_cancel", {reason: String(e?.name || e)})
      }
    })

    this.handleEvent("passkey:authenticate", async ({options}) => {
      try {
        const cred = await navigator.credentials.get({publicKey: reviveRequestOptions(options)})
        this.pushEvent("passkey_assertion", {credential: serializeAssertion(cred)})
      } catch (e) {
        this.pushEvent("passkey_cancel", {reason: String(e?.name || e)})
      }
    })
  },
}

export default Passkey
