import std/[unittest, random]
import warble


randomize()

suite "warble":
  var injectedPayload: seq[uint8]
  test "inject":
    injectedPayload = inject("warble/test-files/test3.png", "warble/test-files/warble.png", "warble/test-files/test3-inj.png")
    assert(injectedPayload.len < profileImage("warble/test-files/test3.png"))

  test "extract":
    var payload = extract("warble/test-files/test3-inj.png", "warble/test-files/warble-out.png")
    assert(payload.len == 2360)
    # payload from "inject" test == extracted payload
    assert(injectedPayload == payload)  
  
  test "profile":  
    # Profile image to get amount of bytes we can fit into it
    var s = profileImage("warble/test-files/test3.png")
    assert s == 518382
  
  test "capacity-limits":
    var s = profileImage("warble/test-files/test3.png")
    # Create fake payload with maximum capacity that can fit
    # inside the given image file.
    var fakePayload = block:
      var res = newSeq[uint8](s)
      var i = 0i64
      for fakeByte in 1..(s):
        res[i] = rand(0..255).uint8
        i += 1
      res
    
    # Save fake payload
    var f: File
    discard f.open("warble/test-files/fakePayload", fmWrite)
    discard f.writeBytes(fakePayload, 0, s)
    f.close()

    # Inject fake payload into the image and extract the payload
    injectedPayload = inject("warble/test-files/test3.png", "warble/test-files/fakePayload", "warble/test-files/test3-inj.png")
    var extractedPayload = extract("warble/test-files/test3-inj.png", "warble/test-files/fakePayloadExtract")

    assert extractedPayload.len == fakePayload.len
    assert extractedPayload == fakePayload

  test "file size":
    var fileSize = fileBytesSize("warble/test-files/test3.png")
    assert fileSize == 1789041


