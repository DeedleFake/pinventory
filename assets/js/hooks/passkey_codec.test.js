import assert from "node:assert/strict"
import {describe, it} from "node:test"
import {fromB64url, reviveRequestOptions, serializeAssertion, toB64url} from "./passkey_codec.js"

describe("passkey codec", () => {
  it("round-trips base64url without padding", () => {
    const bytes = new Uint8Array([0, 251, 255, 62, 63, 1])
    const s = toB64url(bytes.buffer)
    assert.equal(s, "APv_Pj8B")
    assert.deepEqual(new Uint8Array(fromB64url(s)), bytes)
  })

  it("revives challenge and allowCredentials ids", () => {
    const o = reviveRequestOptions({challenge: "AQI", rpId: "localhost", allowCredentials: [{type: "public-key", id: "Aw"}]})
    assert.deepEqual(new Uint8Array(o.challenge), new Uint8Array([1, 2]))
    assert.deepEqual(new Uint8Array(o.allowCredentials[0].id), new Uint8Array([3]))
    assert.equal(o.rpId, "localhost")
  })

  it("serializes an assertion with a null user handle", () => {
    const buf = (n) => new Uint8Array([n]).buffer
    const out = serializeAssertion({
      id: "x", rawId: buf(1), type: "public-key",
      response: {clientDataJSON: buf(2), authenticatorData: buf(3), signature: buf(4), userHandle: null},
    })
    assert.deepEqual(out.response, {clientDataJSON: "Ag", authenticatorData: "Aw", signature: "BA", userHandle: null})
    assert.equal(out.rawId, "AQ")
  })
})
