<p align="center">
  <img src="warble/test-files/warble.png">
</p>

Warble is a tiny command line steganography tool/nim library that can embed files into the pixel data of images, or into the data chunk of a wav file.

Encoding/decoding functions for images based on the steganography library by treeform:

https://github.com/treeform/steganography

## Installation / Compiling

For use as a nim library, download this repository and run `nimble install` in the repository's directory or run `nimble install https://github.com/RattleyCooper/warble`

You can run `nimble test`, to run the tests, but this is not required.

If you wish to use this as an executable, get the nim compiler from https://nim-lang.org/install.html and run the following in the warble directory:

`nim c -d:release -d:danger --opt:speed warble.nim`

If you are on linux and want to read JPG images, run the following in the warble directory:

`nim c -d:release -d:danger -d:pixieUseStb --opt:speed warble.nim`

Note that warble is limited to the image formats that [`pixie`](https://github.com/treeform/pixie) can work with. Get the latest pixie update to fix the broken JPEG bug.

## Uses

This was made as a proof of concept data infil/exfil tool, but there are legitimate uses as well. It could be used in game development to embed map data in an image of the map itself. Games like spore are known to use steganography in a similar way for sharing creatures.

https://nedbatchelder.com/blog/200806/spore_creature_creator_and_steganography.html

## Examples

Profiling a file to see exactly how many bytes we can fit into it:

```
./warble --pr: test-files/test0.png
1457985 available bytes
```

* `--pr: filepath`    filepath of image you want to profile

## Inject a payload into an image

All of the following commands work with images or wav files. Warble will detect what type of file and do the correct encoding/decoding

The following command injects the `warble` binary into one of the test images.

```
./warble --i: test-files/test2.png --o: test-files/test2-inj.png --p: warble
```

Output

```
Inject : 

  Input Image:	test-files/test2.png
  Output Image:	test-files/test2-inj.png
  Payload Path:	warble

Opening payload...
Payload size: 521624
Reading payload...
Reading image data...
Injecting payload... 521624
Writing image payload..
Done.
```

* `--i: filepath`    input filepath
* `--o: filepath`    output filepath
* `--p: filepath`     filepath to payload

If the `--i`, `--o` and `--p` arguments are set, the payload will be embedded into the input and saved to the output.

## Extract a payload from a file

The following command extracts the payload from the input and saves it to `test-files/warble`

```
./warble --i: test-files/test2-inj.png --p: test-files/warble
```

Output

```
Extract : 

  Input Image:	test-files/test2-inj.png
  Payload Path:	test-files/warble

Reading image data...
Extracting payload...
Payload size: 521624
Creating payload file...
Writing payload... 521624
Done.
```

* `--i: filepath`    input filepath
* `--p: filepath`     output filepath

When the `--i` and `--p` arguments are set the payload will be read from the input and saved as the file specified by `--p`
