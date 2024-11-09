# seizer

`seizer` is a Zig library for making software rendered Wayland applications.
It is currently in an alpha state, and the APIs constantly break.

## Features

-   Wayland native (using the [`shimizu`][] module)
-   Handles setting up a [`libxev`][] event loop
-   `color` module for sRGB gamma encoding and decoding
-   2d Canvas API, targeting realtime rendering:
    -   `fillRect`
    -   `textureRect`
    -   `line`
-   A `ui` module exposing some high level elements:
    -   `ui.Element.Label`
    -   `ui.Element.Button`
    -   `ui.Element.TextField`
    -   `ui.Element.FlexBox`
    -   `ui.Element.Frame`
    -   `ui.Element.Image`
    -   `ui.Element.PanZoom`
    -   `ui.Element.Plot`

[`shimizu`]: https://git.sr.ht/~geemili/shimizu
[`libxev`]: https://github.com/mitchellh/libxev

## Roadmap

In the future, `seizer` wants to have the following features:

-   [Cached Software Rendering](https://rxi.github.io/cached_software_rendering.html)
-   Shims to run on other platforms
    -   Windows: verify that running through the `WSL` Wayland server works
    -   Web: use the [greenfield HTML5 Wayland compositor](https://github.com/udevbe/greenfield) or make something similar
-   Some way to deploy SIMD optimized functions and fallback functions in a single executable
-   [TrueType font support](https://codeberg.org/andrewrk/TrueType/)
    
## FAQ

> Why is it called "seizer"?

It is a reference to the "Seizer Beam" from the game [Zero Wing][]. Move Zig!

[zero wing]: https://en.wikipedia.org/wiki/Zero_Wing

> Wasn't `seizer` going to have a cross platform windowing API?

I decided to reduce scope. Targeting Wayland specifically means I have to invent
fewer abstractions, and can just focus on supporting what works well on Wayland.
And the Windows `WSLg` project made me realize that the Wayland protocol is just
that; a protocol. There's a few Linux-isms, sure, but nothing fundamentally
stops other OSes from adopting Wayland.

If you want true cross platform windowing support, there are plenty of other
projects doing just that; [SDL][], [GLFW][], [mach][], and [sokol][] just to
name a few.

[SDL]: https://www.libsdl.org/
[GLFW]: https://www.glfw.org/
[mach]: https://machengine.org/
[sokol]: https://github.com/floooh/sokol#sokol

I also realized that I'm not really interested in platforms other than Linux.
Linux is my daily driver OS. I don't use MacOS or Windows (or BSD) and there
are plenty of other developers targeting those platforms.

> Wasn't `seizer` targeting OpenGL/Vulkan at some point?

Yes, it was. For a variety of reasons, I've decided that supporting GPUs is out
of scope:

-   Vulkan is a _huge_ API surface. While it might be possible to write a backend
    that supports it, exposing it's full power takes serious effort. Exposing
    something like `seizer.Canvas` would be much more reasonable than trying to make
    an API that allows using GPUs through either OpenGL or Vulkan (Which is what I
    was trying to do. That part was my fault for tackling too large a scope).
-   `libvulkan` and `libEGL` require using `dlopen`; this is a problem on Linux:
    -   Linux has no system libc; ergo no system `dlopen`
    -   Dynamically linking to `glibc` or `musl` multiplies the number of ways your
        program can break.
-   One the programs that inspired the creation of `seizer` needs to export
    measurement images with additional markup on it, and a software rendering library
    makes this easier.
-   Running statically linked binaries on Linux gives me _dopamine_.
