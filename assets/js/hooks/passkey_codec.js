// base64url <-> ArrayBuffer conversion for WebAuthn options and responses.
// The server sends binary fields base64url-encoded; the browser API wants
// ArrayBuffers, and its responses must go back as base64url.

export function fromB64url(s) {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/")
  const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4)
  const bin = atob(padded)
  const bytes = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
  return bytes.buffer
}

export function toB64url(buf) {
  const bytes = new Uint8Array(buf)
  let bin = ""
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i])
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

const reviveList = (list) => (list || []).map((c) => ({...c, id: fromB64url(c.id)}))

export function reviveCreationOptions(o) {
  return {
    ...o,
    challenge: fromB64url(o.challenge),
    user: {...o.user, id: fromB64url(o.user.id)},
    excludeCredentials: reviveList(o.excludeCredentials),
  }
}

export function reviveRequestOptions(o) {
  return {...o, challenge: fromB64url(o.challenge), allowCredentials: reviveList(o.allowCredentials)}
}

export function serializeAttestation(cred) {
  const r = cred.response
  return {
    id: cred.id,
    rawId: toB64url(cred.rawId),
    type: cred.type,
    response: {
      clientDataJSON: toB64url(r.clientDataJSON),
      attestationObject: toB64url(r.attestationObject),
      transports: typeof r.getTransports === "function" ? r.getTransports() : [],
    },
  }
}

export function serializeAssertion(cred) {
  const r = cred.response
  return {
    id: cred.id,
    rawId: toB64url(cred.rawId),
    type: cred.type,
    response: {
      clientDataJSON: toB64url(r.clientDataJSON),
      authenticatorData: toB64url(r.authenticatorData),
      signature: toB64url(r.signature),
      userHandle: r.userHandle ? toB64url(r.userHandle) : null,
    },
  }
}
