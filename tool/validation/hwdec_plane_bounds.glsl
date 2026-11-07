// Diagnostic candidate for unrotated, uncropped 4:2:0 inputs only.
// Keep the hardware decoder and materialize both planes on the GPU. Clamp before
// interpolation so an aligned decoder surface's padding cannot bleed into the
// visible image. This is deliberately not installed in the production player:
// rotation, crop, other subsampling and pass cost need separate acceptance.
//!HOOK LUMA
//!BIND HOOKED
//!DESC Clamp visible luma before interpolation
vec4 hook() {
    vec2 last_center = (ceil(input_size) - vec2(0.5)) * HOOKED_pt;
    return HOOKED_tex(clamp(HOOKED_pos, 0.5 * HOOKED_pt, last_center));
}

//!HOOK CHROMA
//!BIND HOOKED
//!DESC Clamp visible 4:2:0 chroma before interpolation
vec4 hook() {
    vec2 last_center = (ceil(input_size * 0.5) - vec2(0.5)) * HOOKED_pt;
    return HOOKED_tex(clamp(HOOKED_pos, 0.5 * HOOKED_pt, last_center));
}
