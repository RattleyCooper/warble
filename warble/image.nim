import pixie

proc encodeData*(image: Image, data: seq[uint8]) =
  ## Hide data inside an image
  #

  # Prepend the data length to the data.
  var dataLen: int64 = data.len()
  var dataLenSeq: seq[uint8] = newSeq[uint8](8)
  copyMem(addr dataLenSeq[0], unsafeAddr dataLen, sizeOf(dataLen))
  var ndata: seq[uint8]
  ndata.add dataLenSeq
  ndata.add data

  # Encode all of the data
  for i in 0..ndata.len-1:
    var dataByte: uint8 = ndata[i]
    if i >= ndata.len:
      break
    var
      c1 = image.data[i*2+0]
      c2 = image.data[i*2+1]
    c1.r = (c1.r and 0b11111000) + (dataByte and 0b00000001) shr 0
    c1.g = (c1.g and 0b11111100) + (dataByte and 0b0000110) shr 1
    c1.b = (c1.b and 0b11111000) + (dataByte and 0b0001000) shr 3
    c1.a = 255
    c2.r = (c2.r and 0b11111000) + (dataByte and 0b00110000) shr 4
    c2.g = (c2.g and 0b11111100) + (dataByte and 0b01000000) shr 6
    c2.b = (c2.b and 0b11111000) + (dataByte and 0b10000000) shr 7
    c2.a = 255
    image.data[i*2+0] = c1
    image.data[i*2+1] = c2

proc decodeData*(image: Image): seq[uint8] =
  ## Extract hidden data in the image
  #

  # Extract the data's length.
  var dataLen: int64
  var dataLenBytes: seq[uint8] = newSeq[uint8](8)
  for i in 0..7:
    var dataByte: uint8
    let
      c1 = image.data[i*2+0]
      c2 = image.data[i*2+1]
    dataByte += (c1.r and 0b1) shl 0
    dataByte += (c1.g and 0b11) shl 1
    dataByte += (c1.b and 0b1) shl 3
    dataByte += (c2.r and 0b11) shl 4
    dataByte += (c2.g and 0b1) shl 6
    dataByte += (c2.b and 0b1) shl 7

    dataLenBytes[i] = dataByte
  
  copyMem(addr dataLen, unsafeAddr dataLenBytes[0], sizeof(dataLen))

  # Extract data from image.
  for i in 8..<(image.data.len div 4):
    var dataByte: uint8
    let
      c1 = image.data[i*2+0]
      c2 = image.data[i*2+1]
    dataByte += (c1.r and 0b1) shl 0
    dataByte += (c1.g and 0b11) shl 1
    dataByte += (c1.b and 0b1) shl 3
    dataByte += (c2.r and 0b11) shl 4
    dataByte += (c2.g and 0b1) shl 6
    dataByte += (c2.b and 0b1) shl 7

    if result.len >= dataLen:
      break
        
    result.add(dataByte)

proc profileImage*(inImgPath: string): int64 =
  ## The amount of bytes can be stored inside an image.
  #
  var image = readImage(inImgPath)
  result = ((image.width * image.height) div 4) - 8

proc profileImage*(image: Image): int64 =
  ## The amount of bytes can be stored inside an image.
  #
  result = ((image.width * image.height) div 4) - 8

proc inject*(inImgPath: string, plPath: string, outImgPath: string): seq[uint8] =
  ## Inject the payload into the image and create a new image.
  #
  if isMainModule:
    echo "Inject : \n" 
    echo "  Input Image:\t" & inImgPath
    echo "  Output Image:\t" & outImgPath
    echo "  Payload Path:\t" & plPath
    echo "\nOpening payload..."
  var f: File
  discard f.open(plPath, fmRead)
  
  if isMainModule: echo "Payload size: " & $f.getFileSize
  var bytes = newSeq[uint8](f.getFileSize)
  
  if isMainModule: echo "Reading payload..."
  discard f.readBytes(bytes, 0, f.getFileSize)
  
  if isMainModule: echo "Reading image data..."
  var image = readImage(inImgPath)
  doAssert(
    f.getFileSize <= profileImage(image),
    "Cannot fit payload into the given image."
  )
  
  if isMainModule: echo "Injecting payload... " & $bytes.len
  encodeData(image, bytes)
  
  if isMainModule: echo "Writing image payload.."
  image.writeFile(outImgPath)
  f.close()
  
  if isMainModule: echo "Done."
  result = bytes

proc extract*(inImgPath: string, plPath: string, assertSize: int = 0): seq[uint8] =
  ## Extract payload from an image.
  #
  if isMainModule:
    echo "Extract : \n"
    echo "  Input Image:\t" & inImgPath
    echo "  Payload Path:\t" & plPath
    echo "\nReading image data..."
  var image = readImage(inImgPath)
  
  if isMainModule: echo "Extracting payload..."
  var payload = decodeData(image)

  if isMainModule: echo "Payload size: " & $payload.len
  if assertSize > 0:
    doAssert(payload.len == assertSize, "Size of payload did not match the assertSize")
  
  if isMainModule: echo "Creating payload file..."
  var ouf: File
  discard ouf.open(plPath, fmWrite)
  
  if isMainModule: echo "Writing payload... " & $payload.len
  discard ouf.writeBytes(payload, 0, payload.len)
  ouf.close()
  
  if isMainModule: echo "Done."
  result = payload

