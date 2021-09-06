import std/[unittest]
import warble


suite "warble":
  var injectedPayload: seq[uint8]
  test "inject":
    echo "Injecting payload..."
    injectedPayload = inject("warble/test-files/test3.png", "warble/test-files/warble.png", "warble/test-files/test3-inj.png")
    assert(injectedPayload.len < profileImage("warble/test-files/test3.png")-TermBytes.len)

  test "extract":
    echo "Extracting payload..."
    var payload = extract("warble/test-files/test3-inj.png", "warble/test-files/warble-out.png")
    assert(payload.len == 2360)
    assert(injectedPayload == payload)

  test "profile":
    echo "Profiling Image..."
    
    var s = profileImage("warble/test-files/test3.png")
    assert s == 518382

  test "file size":
    var fileSize = fileBytesSize("warble/test-files/test3.png")
    assert fileSize == 1789041


