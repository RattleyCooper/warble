# Warble

Warble is a commind line steganography tool that can embed files into the pixel data of images.  You can also import warble to use programatically with nim.

Encoding/decoding functions based on the steganography library by treeform:

https://github.com/treeform/steganography

## Uses

This was made as a proof of concept data infil/exfil tool, but there are legitimate uses as well.  It could be used in game development to embed map data in an image of the map itself.   Games like spore are known to use steganography in a similar way for sharing creatures.

https://nedbatchelder.com/blog/200806/spore_creature_creator_and_steganography.html

## Examples

Profiling an image to see how many bytes we can fit into it:

`./warble --pr=/some/img/path.png`

* `--pr`    filepath of image you want to profile

### Injecting a payload into an image

`./warble -i --ii=/some/img/path.png --oi=/some/output/img.png --p=/some/payload/to/inject`

* `-i`      tell warble to run in inject mode
* `--ii`    input image filepath
* `--oi`    output image filepath for injected image
* `--p`     input payload to inject into the output image

### Extracting a payload from an image

`./warble -e --ii=/some/injected/img/path.png --p=/some/payload/path`

* `-e`      tell warble to run in extract mode
* `--ii`    input image filepath
* `--p`     output payload path

