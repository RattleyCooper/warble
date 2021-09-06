<p align="center">
  <img src="warble/test-files/warble.png">
</p>

Warble is a command line steganography tool/nim library that can embed files into the pixel data of images.

Encoding/decoding functions based on the steganography library by treeform:

https://github.com/treeform/steganography

## Uses

This was made as a proof of concept data infil/exfil tool, but there are legitimate uses as well.  It could be used in game development to embed map data in an image of the map itself.   Games like spore are known to use steganography in a similar way for sharing creatures.

https://nedbatchelder.com/blog/200806/spore_creature_creator_and_steganography.html

## Installation

Download this repository and run `nimble install` in the repository's directory.

## Examples

Profiling an image to see how many bytes we can fit into it:

```
./warble --pr=test-files/test0.png
1457985 available bytes
```

* `--pr`    filepath of image you want to profile

### Inject a payload into an image

The following command injects the `warble` binary into one of the test images.

```
./warble -i --ii=test-files/test0.png --oi=test-files/test0-inj.png --p=warble
Opening payload...
Payload size: 471928
Injecting payload... 471928
```

* `-i`      tell warble to run in inject mode
* `--ii`    input image filepath
* `--oi`    output image filepath for injected image
* `--p`     input payload to inject into the output image

### Extract a payload from an image

The following command extracts the payload from the injected image and names it `warble`

```
./warble -e --ii=test-files/test0-inj.png --p=test-files/warble
Extracting payload...
Payload size: 471928
Creating payload... 471928
```

* `-e`      tell warble to run in extract mode
* `--ii`    input image filepath
* `--p`     output payload path

