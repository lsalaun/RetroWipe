"""Shared helpers for the PSX WipEout track converters (convert_track_geometry.py,
convert_track_sections.py). See convert_track_geometry.py's module docstring
for why reads are big-endian and why Y gets negated by default.
"""

from __future__ import annotations


def make_axis_transform(flip_z: bool):
    def transform(v: tuple[float, float, float]) -> tuple[float, float, float]:
        x, y, z = v
        return (x, -y, -z if flip_z else z)

    # An odd number of negated axes flips triangle winding/handedness.
    reverse_winding = not flip_z
    return transform, reverse_winding
