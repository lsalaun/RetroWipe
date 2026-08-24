"""Shared helpers for the PSX WipEout track converters (convert_track_geometry.py,
convert_track_sections.py). See convert_track_geometry.py's module docstring
for why reads are big-endian and why Y gets negated by default.
"""

from __future__ import annotations

# Derived from TRACK01/Altima VII: its documented real-world lap length
# (~5500m, wipeout.fandom.com/wiki/Altima_VII) divided by the raw length of
# the TRACK.TRS centerline (585969 raw units) = ~106.5 raw units per meter.
# A cross-check from the documented elevation change (359m vs 11948 raw units
# of Y range) gives ~33.3 instead -- an unresolved ~3.2x discrepancy, see
# docs/.transactional/26-08-24-02/audit/physique_vaisseau_audit.md point 4.
# Treat this as an estimate: override with --units-per-meter if a better
# figure turns up, or pass 1.0 to keep raw PSX units unscaled.
DEFAULT_UNITS_PER_METER = 106.5


def make_axis_transform(flip_z: bool):
    def transform(v: tuple[float, float, float]) -> tuple[float, float, float]:
        x, y, z = v
        return (x, -y, -z if flip_z else z)

    # An odd number of negated axes flips triangle winding/handedness.
    reverse_winding = not flip_z
    return transform, reverse_winding


def scale_point(v: tuple[float, float, float], units_per_meter: float) -> tuple[float, float, float]:
    """Converts a raw-PSX-unit position (already axis-transformed) to meters.

    Only for positions/centers, never for normals or other pure directions --
    dividing a direction by a scalar keeps it pointing the same way but no
    longer unit-length.
    """
    return (v[0] / units_per_meter, v[1] / units_per_meter, v[2] / units_per_meter)
