// The plan of Jerusalem around AD 30, in longitude and latitude, shared by
// the map's overlay (widgets/jerusalem_map.dart) and the painted city under it
// (tool/build_jerusalem_image.dart). Plain Dart, so the tool can read it.
//
// Original, schematic reconstruction: approximate footprints, not digitized
// excavation plans. See doc/jerusalem-map.md for dating, evidence and
// uncertainties.

/// A wall, building, pool, valley, way or labelled site of the plan.
class PlanFeature {
  const PlanFeature(this.label, this.kind, this.points, this.at);
  final String label;

  /// wall, precinct, building, pool, valley, road, aqueduct, bridge, district
  /// or site.
  final String kind;

  /// Longitude, latitude pairs; a closed shape repeats its first point.
  final List<double> points;

  /// Where the label goes: longitude, latitude.
  final (double, double) at;
}

/// West, south, east and north, in degrees.
const jerusalemBox = (35.224, 31.768, 35.247, 31.784);

const jerusalemPlan = <PlanFeature>[
  PlanFeature(
    'First Wall · approximate',
    'wall',
    [
      35.2280,
      31.7770,
      35.2300,
      31.7766,
      35.2337,
      31.7767,
      35.2355,
      31.7754,
      35.2361,
      31.7730,
      35.2355,
      31.7710,
      35.2340,
      31.7700,
      35.2310,
      31.7698,
      35.2275,
      31.7705,
      35.2268,
      31.7730,
      35.2270,
      31.7752,
      35.2280,
      31.7770,
    ],
    (35.2281, 31.7701),
  ),
  PlanFeature(
    'Second Wall · conjectural',
    'wall',
    [
      35.2280,
      31.7770,
      35.2308,
      31.7775,
      35.2316,
      31.7794,
      35.2324,
      31.7810,
      35.2348,
      31.7808,
    ],
    (35.2312, 31.7800),
  ),
  PlanFeature(
    'Temple precinct',
    'precinct',
    [
      35.2342,
      31.7757,
      35.2371,
      31.7760,
      35.2379,
      31.7807,
      35.2347,
      31.7810,
      35.2342,
      31.7757,
    ],
    (35.2360, 31.7796),
  ),
  PlanFeature(
    'Sanctuary',
    'building',
    [
      35.2348,
      31.7777,
      35.2355,
      31.7777,
      35.2355,
      31.7784,
      35.2348,
      31.7784,
      35.2348,
      31.7777,
    ],
    (35.2351, 31.7787),
  ),
  PlanFeature(
    'Court of Women / treasury',
    'building',
    [
      35.2356,
      31.7777,
      35.2362,
      31.7777,
      35.2362,
      31.7784,
      35.2356,
      31.7784,
      35.2356,
      31.7777,
    ],
    (35.2360, 31.7774),
  ),
  PlanFeature(
    'Royal portico',
    'building',
    [
      35.2344,
      31.7760,
      35.2370,
      31.7763,
      35.2370,
      31.7766,
      35.2344,
      31.7763,
      35.2344,
      31.7760,
    ],
    (35.2357, 31.7756),
  ),
  PlanFeature(
    'Solomon’s portico',
    'building',
    [
      35.2370,
      31.7764,
      35.2376,
      31.7805,
      35.2378,
      31.7805,
      35.2372,
      31.7764,
      35.2370,
      31.7764,
    ],
    (35.2388, 31.7793),
  ),
  PlanFeature(
    'Antonia · alternative trial tradition',
    'building',
    [
      35.2338,
      31.7807,
      35.2353,
      31.7807,
      35.2353,
      31.7815,
      35.2338,
      31.7815,
      35.2338,
      31.7807,
    ],
    (35.2339, 31.7820),
  ),
  PlanFeature(
    'Herod’s palace · likely praetorium',
    'building',
    [
      35.2270,
      31.7738,
      35.2290,
      31.7738,
      35.2290,
      31.7768,
      35.2270,
      31.7768,
      35.2270,
      31.7738,
    ],
    (35.2272, 31.7733),
  ),
  PlanFeature('Upper City', 'district', [], (35.2302, 31.7748)),
  PlanFeature('Lower City / City of David', 'district', [], (35.2353, 31.7728)),
  PlanFeature(
    'Bethesda pools',
    'pool',
    [
      35.2353,
      31.7817,
      35.2360,
      31.7817,
      35.2360,
      31.7824,
      35.2353,
      31.7824,
      35.2353,
      31.7817,
    ],
    (35.2365, 31.7827),
  ),
  PlanFeature(
    'Pool of Siloam · sent man’s destination',
    'pool',
    [
      35.2345,
      31.7701,
      35.2354,
      31.7701,
      35.2354,
      31.7706,
      35.2345,
      31.7706,
      35.2345,
      31.7701,
    ],
    (35.2362, 31.7695),
  ),
  PlanFeature(
    'Kidron valley',
    'valley',
    [
      35.2390,
      31.7840,
      35.2390,
      31.7810,
      35.2390,
      31.7780,
      35.2376,
      31.7745,
      35.2368,
      31.7715,
      35.2360,
      31.7690,
    ],
    (35.2393, 31.7745),
  ),
  PlanFeature(
    'Tyropoeon valley',
    'valley',
    [
      35.2315,
      31.7820,
      35.2327,
      31.7790,
      35.2336,
      31.7760,
      35.2338,
      31.7730,
      35.2349,
      31.7702,
    ],
    (35.2332, 31.7740),
  ),
  PlanFeature(
    'Hinnom valley',
    'valley',
    [
      35.2250,
      31.7780,
      35.2250,
      31.7740,
      35.2257,
      31.7710,
      35.2280,
      31.7688,
      35.2320,
      31.7682,
      35.2360,
      31.7690,
    ],
    (35.2291, 31.7687),
  ),
  PlanFeature('Golgotha / tomb · traditional vicinity', 'site', [], (
    35.2297,
    31.7785,
  )),
  PlanFeature('Garden Tomb · alternative tradition', 'site', [], (
    35.2298,
    31.7838,
  )),
  PlanFeature('Upper room · estimated', 'site', [], (35.2285, 31.7718)),
  PlanFeature('High-priestly quarter · estimated', 'site', [], (
    35.2325,
    31.7715,
  )),
  PlanFeature('Gethsemane · traditional vicinity', 'site', [], (
    35.2397,
    31.7793,
  )),
  PlanFeature('Mount of Olives', 'district', [], (35.2450, 31.7790)),
  PlanFeature('Southern steps / Huldah gates', 'site', [], (35.2355, 31.7752)),
  // The stepped street excavated from 2004 to 2019, laid under Pilate, from
  // the Siloam pool up the Tyropoeon to the Temple's south-west corner.
  PlanFeature(
    'Pilgrims’ road · stepped street',
    'road',
    [
      35.2352,
      31.7706,
      35.2350,
      31.7716,
      35.2346,
      31.7728,
      35.2343,
      31.7740,
      35.2341,
      31.7751,
      35.2341,
      31.7759,
    ],
    (35.2334, 31.7722),
  ),
  // The lower-level aqueduct from Solomon's Pools, round the south of the
  // western hill and up the Tyropoeon to cross on Wilson's Arch.
  PlanFeature(
    'Lower aqueduct',
    'aqueduct',
    [
      35.2240,
      31.7700,
      35.2262,
      31.7702,
      35.2285,
      31.7700,
      35.2310,
      31.7703,
      35.2327,
      31.7711,
      35.2332,
      31.7730,
      35.2334,
      31.7750,
      35.2335,
      31.7769,
    ],
    (35.2300, 31.7708),
  ),
  PlanFeature(
    'Wilson’s Arch bridge',
    'bridge',
    [35.2328, 31.7769, 35.2343, 31.7769],
    (35.2322, 31.7774),
  ),
  // Mishnah Parah 3:6 describes a causeway of arches from the Temple Mount
  // over the Kidron to the Mount of Olives; no remains are identified.
  PlanFeature(
    'Kidron bridge · Mishnah tradition',
    'bridge',
    [35.2375, 31.7787, 35.2403, 31.7789],
    (35.2408, 31.7780),
  ),
];
