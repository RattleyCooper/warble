import streams, strutils

type
  Wav = ref object
    filename: string
    dataPos: int
    data: seq[uint8]

proc isWav*(filepath: string): bool =
  ## Check for the RIFF header of a wav file and return
  ## true if it's found.
  let fs = newFileStream(filepath, fmRead)
  if fs == nil:
    if isMainModule:
      echo "Could not open ", filepath
    quit QuitFailure

  var header: string = newString(4)
  discard fs.readDataStr(header, 0..3)
  if header == "RIFF":
    return true
  return false

proc decodeWav*(wav: Wav): seq[uint8] =
  ## Decodes the payload embedded in the LSB of the WAV file's data chunk.
  ## Returns the decoded payload as a sequence of bytes.
  var bitIndex = 0
  var payloadLenBytes: array[8, uint8]  # To store the 8-byte payload length
  var payloadLen: int64 = 0

  # Extract the payload length (8 bytes)
  for i in 0..<8:
    for j in 0..<8:
      let sampleIndex = bitIndex * 4  # Each sample is 4 bytes
      var sample: float32
      copyMem(addr sample, addr wav.data[sampleIndex], 4)  # Read float32 sample
      let byteRep = cast[array[4, uint8]](sample)
      let bit = byteRep[0] and 1  # Extract LSB of the least significant byte
      payloadLenBytes[i] = (payloadLenBytes[i] shl 1) or bit  # Reconstruct byte
      bitIndex += 1

  # Convert the 8-byte array to an int64
  copyMem(addr payloadLen, addr payloadLenBytes[0], 8)

  if isMainModule:
    echo "Decoded payload length: ", payloadLen

  # Extract the payload
  var payload: seq[uint8] = newSeq[uint8](payloadLen)
  for i in 0..<payloadLen:
    for j in 0..<8:
      let sampleIndex = bitIndex * 4  # Each sample is 4 bytes
      var sample: float32
      copyMem(addr sample, addr wav.data[sampleIndex], 4)  # Read float32 sample
      let byteRep = cast[array[4, uint8]](sample)
      let bit = byteRep[0] and 1  # Extract LSB of the least significant byte
      payload[i] = (payload[i] shl 1) or bit  # Reconstruct byte
      bitIndex += 1

  return payload

proc extractWavData*(filename: string): Wav =
  ## Extract the payload from the given wav file.
  ## 
  result = Wav(filename: "", dataPos: 0, data: newSeq[uint8]())
  result.filename = filename

  let fs = newFileStream(filename, fmRead)
  if fs == nil:
    raise newException(IOError, "Failed to open file")

  defer: fs.close()

  var buffer: array[4, char]
  fs.setPosition(12)  # Skip RIFF header (12 bytes: "RIFF", file size, "WAVE")
  while not fs.atEnd():
    discard fs.readData(addr buffer[0], 4)  # Read 4 bytes (chunk ID)
    let chunkId = buffer.join("")

    var chunkSize: int32
    discard fs.readData(addr chunkSize, 4)  # Read 4-byte chunk size
    
    if chunkId == "data":
      result.dataPos = fs.getPosition()
      result.data = newSeq[uint8](chunkSize)
      discard fs.readData(addr result.data[0], chunkSize)
      return

    fs.setPosition(fs.getPosition() + chunkSize)  # Skip to next chunk

  raise newException(IOError, "No data chunk found")

proc profileWav*(wavPath: string): int64 =
  var w = extractWavData(wavPath)
  result = (w.data.len div 4) div 8
  if isMainModule: echo "Data Cap: ", result

proc encodeWav*(wav: Wav, plPath: string, newPath: string): Wav =
  var f: File
  discard f.open(plPath, fmRead)
  defer: f.close()

  # Create the payload with the length of the payload 
  # added to the beginning of the payload bytes.
  var dataLen: int64 = f.getFileSize()
  var dataLenSeq: seq[uint8] = newSeq[uint8](8)
  copyMem(addr dataLenSeq[0], unsafeAddr dataLen, sizeOf(dataLen))
  var payload: seq[uint8]
  payload.add dataLenSeq

  if isMainModule:
    echo "Payload size: " & $dataLen
    echo "Reading payload..."

  var pdat = newSeq[uint8](f.getFileSize())
  discard f.readBytes(pdat, 0, f.getFileSize())
  payload.add pdat

  if payload.len * 8 > wav.data.len div 4:  # 32-bit samples (4 bytes per sample)
    raise newException(ValueError, "Not enough space for the payload.")

  var bitIndex = 0
  for i in 0..<payload.len:
    for j in 0..<8:
      let bit = (payload[i] shr (7 - j)) and 1
      let sampleIndex = bitIndex * 4  # Each sample is 4 bytes

      # Convert 4 bytes into a float32
      var sample: float32
      copyMem(addr sample, addr wav.data[sampleIndex], 4)  # Read float32

      # Modify the LSB of the last byte (least significant)
      var byteRep = cast[array[4, uint8]](sample)
      byteRep[0] = (byteRep[0] and 0xFE) or bit  # Modify LSB of least significant byte

      # Store modified sample back
      sample = cast[float32](byteRep)
      copyMem(addr wav.data[sampleIndex], addr sample, 4)

      bitIndex += 1

  # Write modified WAV data to a new file
  var nf: File # New wav file
  discard nf.open(newPath, fmWrite)
  defer: nf.close()

  var olf: File # Old wav file
  discard olf.open(wav.filename, fmRead)
  defer: olf.close()

  # Write the header/fmt chunk to the new wav file
  var preData = newSeq[uint8](wav.dataPos + 1)
  discard olf.readBytes(preData, 0, wav.dataPos + 1)
  discard nf.writeBytes(preData, 0, preData.len - 1)
  
  # Write the data chunk to new wav file.
  discard nf.writeBytes(wav.data, 0, wav.data.len)

  # Check for data after the data chunk and
  # write it to the new wav file if it exists
  let fs = olf.getFileSize()
  if fs > wav.dataPos + wav.data.len + 1:
    let remainder = fs - (wav.dataPos + 1 + wav.data.len)
    var rBytes = newSeq[uint8](remainder)
    olf.setFilePos(olf.getFileSize - remainder - 1)
    discard olf.readBytes(rBytes, 0, remainder)
    discard nf.writeBytes(rBytes, 0, rBytes.len)
  return wav

