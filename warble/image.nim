from pixie import Image, readImage, writeFile

proc encodeData*(image: Image, data: seq[uint8]) =
  ## Hide data inside an image
  #
  # Prepend the data length (8 bytes) to the data.
  var dataLen: int64 = data.len
  let total = 8 + data.len
  var ndata = newSeq[uint8](total)
  copyMem(addr ndata[0], unsafeAddr dataLen, sizeOf(dataLen))
  ndata[8..<total] = data

  # Encode every byte into two image pixels.
  for i in 0..<total:
    let dataByte = ndata[i]
    let pixIndex = i shl 1  # equivalent to i*2
    var c1 = image.data[pixIndex]
    var c2 = image.data[pixIndex + 1]

    # Embed the lower bits into c1, upper bits into c2.
    c1.r = (c1.r and 0xF8) or (dataByte and 0x01)
    c1.g = (c1.g and 0xFC) or ((dataByte shr 1) and 0x03)
    c1.b = (c1.b and 0xF8) or ((dataByte shr 3) and 0x01)
    c2.r = (c2.r and 0xF8) or ((dataByte shr 4) and 0x03)
    c2.g = (c2.g and 0xFC) or ((dataByte shr 6) and 0x01)
    c2.b = (c2.b and 0xF8) or ((dataByte shr 7) and 0x01)

    c1.a = 255
    c2.a = 255

    image.data[pixIndex] = c1
    image.data[pixIndex + 1] = c2

proc decodeData*(image: Image): seq[uint8] =
  ## Extract hidden data from the image
  #
  # Extract the 8-byte data length.
  var dataLen: int64
  var dataLenBytes = newSeq[uint8](8)
  for i in 0..<8:
    let pixIndex = i shl 1
    let c1 = image.data[pixIndex]
    let c2 = image.data[pixIndex + 1]
    var byte: uint8 = 0
    byte = ((c1.r and 1)       shl 0) or
           ((c1.g and 3)       shl 1) or
           ((c1.b and 1)       shl 3) or
           ((c2.r and 3)       shl 4) or
           ((c2.g and 1)       shl 6) or
           ((c2.b and 1)       shl 7)
    dataLenBytes[i] = byte

  copyMem(unsafeAddr dataLen, addr dataLenBytes[0], sizeOf(dataLen))
  echo "Data Length: ", dataLen

  # Preallocate the result with the exact data length.
  result = newSeq[uint8](dataLen)
  for i in 0..<dataLen:
    let pixIndex = (i + 8) shl 1  # start after the 8 length bytes
    let c1 = image.data[pixIndex]
    let c2 = image.data[pixIndex + 1]
    var byte: uint8 = 0
    byte = ((c1.r and 1)       shl 0) or
           ((c1.g and 3)       shl 1) or
           ((c1.b and 1)       shl 3) or
           ((c2.r and 3)       shl 4) or
           ((c2.g and 1)       shl 6) or
           ((c2.b and 1)       shl 7)
    result[i] = byte

  return result

proc profileImage*(image: Image): int64 =
  ## The amount of bytes can be stored inside an image.
  #
  let totalBits = image.width * image.height * 3
  let availableBits = totalBits - 64

  if availableBits < 0:
    raise newException(ValueError, "Image is too small to store the length header.")

  result = availableBits div 8

proc profileImage*(inImgPath: string): int64 =
  ## Calculates the amount of data (in bytes) that can be stored inside an image.
  ## - Only RGB channels are used (3 bits per pixel).
  ## - The first 8 bytes are reserved for storing the length of the data as an int64.
  ##
  var image = readImage(inImgPath)
  image.profileImage()

proc inject*(inImgPath: string, plPath: string, outImgPath: string): seq[uint8] =
  ## Inject the payload into the image and create a new image.
  #
  echo "Inject : \n" 
  echo "  Input Image:\t" & inImgPath
  echo "  Output Image:\t" & outImgPath
  echo "  Payload Path:\t" & plPath
  echo "\nOpening payload..."
  var f: File
  discard f.open(plPath, fmRead)
  
  echo "Payload size: " & $f.getFileSize
  var bytes = newSeq[uint8](f.getFileSize)
  
  echo "Reading payload..."
  discard f.readBytes(bytes, 0, f.getFileSize)
  
  echo "Reading image data..."
  var image = readImage(inImgPath)
  doAssert(
    f.getFileSize <= profileImage(image),
    "Cannot fit payload into the given image."
  )
  
  echo "Injecting payload... " & $bytes.len
  encodeData(image, bytes)
  
  echo "Writing image payload.."
  image.writeFile(outImgPath)
  f.close()
  
  echo "Done."
  result = bytes

proc extract*(inImgPath: string, plPath: string, assertSize: int = 0): seq[uint8] =
  ## Extract payload from an image.
  #

  echo "Extract : \n"
  echo "  Input Image:\t" & inImgPath
  echo "  Payload Path:\t" & plPath
  echo "\nReading image data..."
  var image = readImage(inImgPath)
  
  echo "Extracting payload..."
  var payload = decodeData(image)

  echo "Payload size: " & $payload.len
  if assertSize > 0:
    doAssert(payload.len == assertSize, "Size of payload did not match the assertSize")
  
  echo "Creating payload file..."
  var ouf: File
  discard ouf.open(plPath, fmWrite)
  
  echo "Writing payload... " & $payload.len
  discard ouf.writeBytes(payload, 0, payload.len)
  ouf.close()
  
  echo "Done."
  result = payload

