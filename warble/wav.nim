from streams import newFileStream, readDataStr, close, atEnd, readData, setPosition, getPosition
from strutils import join

type
  Wav* = ref object
    filename*: string
    dataPos*: int
    data*: seq[uint8]
    audioFormat*: int
    bitsPerSample*: int
    bytesPerSample*: int

proc isWav*(filepath: string): bool =
  ## Check for the RIFF header of a wav file and return
  ## true if it's found.
  #
  let fs = newFileStream(filepath, fmRead)
  if fs == nil:
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
  #
  var bitIndex = 0
  var payloadLenBytes: array[8, uint8]
  var payloadLen: int64 = 0
  let bytesPerSample = wav.bytesPerSample

  # Extract payload length (8 bytes)
  for i in 0..<8:
    for j in 0..<8:
      let sampleIndex = bitIndex * bytesPerSample
      if sampleIndex + bytesPerSample > wav.data.len:
        raise newException(ValueError, "Not enough data to read payload length.")
      let firstByte = wav.data[sampleIndex]
      let bit = firstByte and 1
      payloadLenBytes[i] = (payloadLenBytes[i] shl 1) or bit
      bitIndex += 1

  copyMem(addr payloadLen, addr payloadLenBytes[0], 8)

  echo "Payload size: " & $payloadLen
  echo "Extracting payload..."
  # Extract the payload
  var payload: seq[uint8] = newSeq[uint8](payloadLen)
  for i in 0..<payloadLen:
    for j in 0..<8:
      let sampleIndex = bitIndex * bytesPerSample
      if sampleIndex + bytesPerSample > wav.data.len:
        raise newException(ValueError, "Payload exceeds available data.")
      let firstByte = wav.data[sampleIndex]
      let bit = firstByte and 1
      payload[i] = (payload[i] shl 1) or bit
      bitIndex += 1

  return payload

proc extractWavData*(filename: string): Wav =
  ## Extract the payload from the given wav file.
  #
  result = Wav(filename: "", dataPos: 0, data: newSeq[uint8](), audioFormat: 1, bitsPerSample: 16, bytesPerSample: 2)
  result.filename = filename

  let fs = newFileStream(filename, fmRead)
  if fs == nil:
    raise newException(IOError, "Failed to open file")

  defer: fs.close()

  var buffer: array[4, char]
  fs.setPosition(12)  # Skip RIFF header
  while not fs.atEnd():
    discard fs.readData(addr buffer[0], 4)
    let chunkId = buffer.join("")

    var chunkSize: int32
    discard fs.readData(addr chunkSize, 4)

    if chunkId == "fmt ":
      var fmtData: array[16, uint8]
      discard fs.readData(addr fmtData[0], 16)
      var audioFormat: int16
      copyMem(addr audioFormat, addr fmtData[0], 2)
      result.audioFormat = int(audioFormat)
      var bitsPerSample: int16
      copyMem(addr bitsPerSample, addr fmtData[14], 2)
      result.bitsPerSample = int(bitsPerSample)
      result.bytesPerSample = result.bitsPerSample div 8
      let remainingChunkSize = int(chunkSize) - 16
      if remainingChunkSize > 0:
        fs.setPosition(fs.getPosition() + remainingChunkSize)
    elif chunkId == "data":
      result.dataPos = fs.getPosition()
      result.data = newSeq[uint8](int(chunkSize))
      discard fs.readData(addr result.data[0], int(chunkSize))
      return
    else:
      fs.setPosition(fs.getPosition() + int(chunkSize))
  raise newException(IOError, "No data chunk found")

proc profileWav*(wavPath: string): int64 =
  ## Calculates the amount of data (in bytes) that can be stored inside a WAV file.
  ## Reserves 8 bytes for an int64 length header.
  #
  var w = extractWavData(wavPath)
  let totalSamples = w.data.len div w.bytesPerSample
  let availableBits = totalSamples - 64  # 64 bits for the header
  if availableBits < 0:
    raise newException(ValueError, "WAV file is too small to store the length header.")

  result = availableBits div 8
  echo "Data Cap: ", result

proc encodeWav*(wav: Wav, plPath: string, newPath: string): Wav =
  ## Encode a payload into the LSB of each sample of a Wav file
  #
  var f: File
  discard f.open(plPath, fmRead)
  defer: f.close()

  echo "Payload size: " & $f.getFileSize()
  var dataLen: int64 = f.getFileSize()
  var dataLenSeq: seq[uint8] = newSeq[uint8](8)
  copyMem(addr dataLenSeq[0], unsafeAddr dataLen, sizeof(dataLen))
  var payload: seq[uint8]
  payload.add(dataLenSeq)

  echo "Reading payload..."
  var pdat = newSeq[uint8](f.getFileSize())
  discard f.readBytes(pdat, 0, f.getFileSize())
  payload.add(pdat)

  let totalSamples = wav.data.len div wav.bytesPerSample
  if (payload.len * 8) > totalSamples:
    raise newException(ValueError, "Not enough space for the payload.")

  echo "Injecting payload... " & $payload.len
  var bitIndex = 0
  let bytesPerSample = wav.bytesPerSample
  for i in 0..<payload.len:
    for j in 0..<8:
      let bit = (payload[i] shr (7 - j)) and 1
      let sampleIndex = bitIndex * bytesPerSample
      if sampleIndex >= wav.data.len:
        raise newException(ValueError, "Sample index exceeds data length.")
      # Modify the first byte of the sample
      wav.data[sampleIndex] = (wav.data[sampleIndex] and 0xFE) or uint8(bit)
      bitIndex += 1

  echo "Writing payload to wav.."
  # Write modified WAV data to a new file
  var nf: File
  discard nf.open(newPath, fmWrite)
  defer: nf.close()

  var olf: File
  discard olf.open(wav.filename, fmRead)
  defer: olf.close()

  # Write the header up to data chunk
  var preData = newSeq[uint8](wav.dataPos)
  olf.setFilePos(0)
  discard olf.readBytes(preData, 0, wav.dataPos)
  discard nf.writeBytes(preData, 0, preData.len)
  
  # Write the modified data chunk
  discard nf.writeBytes(wav.data, 0, wav.data.len)

  # Write remaining data after the data chunk if any
  let remainingStart = wav.dataPos + wav.data.len
  olf.setFilePos(remainingStart)
  let remainingBytes = olf.getFileSize() - remainingStart
  if remainingBytes > 0:
    var remainder = newSeq[uint8](remainingBytes)
    discard olf.readBytes(remainder, 0, remainingBytes)
    discard nf.writeBytes(remainder, 0, remainingBytes)

  return wav