# FS51

A compatibility layer that makes formspec_version 4 (and later) formspecs
render more correctly in Minetest 5.3.0 and earlier.

This will work with most mods without any additional configuration. If you want
to disable automatic formspec translation, add
`fs51.disable_monkey_patching = true` to minetest.conf.

## Why?

Minetest 5.1.0 introduced changes to formspecs that made them much less painful
to create and work with. However, formspecs are interpreted client-side and to
take advantage of these changes you would normally need to force everyone to
upgrade Minetest. This mod detects these older clients and modifies formspecs
sent to them to try and make sure they are at least usable.

## How to use

1. Install the mod
2. Hope it works properly and doesn't break anything

## Limitations

FS51 replaces some newer formspec elements with fallbacks if clients don't
support them, however this does have some limitations:

 - Animated images will just display their first frame.
 - Fullscreen background colours (the `fbgcolor` value in `bgcolor`) don't
   work.
 - Hypertext elements will lose all formatting and interactivity.
 - Models will just display their underlying texture.
 - Scroll containers are broken.
 - `button_url[]` behaves equivalently to `button_url_exit[]`.

## Troubleshooting

 - If your mod stores `minetest.show_formspec` during load time, you'll need to
   add `fs51` as an optional dependency to `mod.conf` so it can use the patched
   show_formspec code.
 - If you need to have node meta formspecs work in older clients, try adding
   `fs51.disable_meta_override = false` to minetest.conf. Note that FS51 does
   not correctly parse `${key}` syntax (see https://gitlab.com/luk3yx/minetest-fs51/-/issues/1),
   I recommend using `minetest.show_formspec` instead if possible as FS51 is
   also able to perform backports based on the client's version.

## Dependencies

This mod depends on my [formspec_ast] library.

## API functions

You probably don't need to use these unless you're embedding fs51 outside of
Minetest.

 - `fs51.backport(tree)`: Applies backports to a [formspec_ast] tree and
    returns the modified tree. This does not modify the existing tree in place.
 - `fs51.backport_string(formspec)`: Similar to
    `formspec_ast.unparse(fs51.backport(formspec_ast.parse(formspec)))`.

*Unlike the automatic backporting, these functions will preserve newer elements
such as hypertext and background9 so the formspec will still work properly with
newer clients.*

 [formspec_ast]: https://content.minetest.net/packages/luk3yx/formspec_ast
