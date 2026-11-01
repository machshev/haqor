# Jerusalem around AD 30

The **Jerusalem · AD 30** control appears on place and sequence maps containing
Jerusalem-area pins. It fits the ancient city, enables the historical layer and
allows zooming to individual buildings. Event pins retain their usual selection
behaviour. The information button explains the reconstruction and opens sources.
The layer is opt-in elsewhere: other periods of the Bible are not silently shown
on an AD 30 city plan. The sequence maps of Jesus' ministry, Holy Week, the
priestly and Roman hearings and the resurrection appearances show it always,
without the hide button.

`lib/src/jerusalem_plan.dart` contains an original schematic reconstruction
in longitude/latitude, not a traced or reproduced archaeological map. Footprints
are approximate and are intentionally not survey precision. It shows the First
Wall, a conjectural Second Wall, Temple precinct and interior courts, Antonia,
Herod's western palace, pools, valleys and contextual landmarks. It excludes the
Third Wall (begun under Agrippa I, after Jesus' ministry) and Ottoman walls.
Dashed wall lines denote reconstruction, not preserved stretches. The north arrow
and metric bar use the map projection; court labels appear at closer zoom.

## Evidence and choices

- [University of Michigan: Jerusalem wall phases](https://image-database.nes.lsa.umich.edu/items/show/299)
  distinguishes the walls and documents uncertainty about the Second Wall.
- [Temple layout and ancient descriptions](https://www.katapi.org.uk/Architecture/TempleMount30ce.html)
  collects Josephus and Mishnah references for the precinct and courts.
- [Second Temple archaeology](https://jewishvirtuallibrary.org/jsource/Archaeology/Jerusalem.html)
  describes the western palace and Upper City archaeology.
- [The praetorium traditions](https://www.terrasanctamuseum.org/en/discover-more/the-praetorium-of-pilate-and-the-house-of-herod/)
  documents the history of the alternative eastern location.

The western palace is the working estimate for Pilate's praetorium; the Antonia
tradition remains a labelled alternative. The upper room, Annas, Caiaphas,
the council and Herod Antipas' lodging have separate *estimated* core records.
Their distinct coordinates make movements readable, not archaeological claims.
Golgotha and the nearby tomb use the Holy Sepulchre vicinity; the Garden Tomb is
labelled as an alternative, not a second stop. No modern Via Dolorosa street
itinerary is asserted. Connections between event sites remain illustrative.

Siloam is a background landmark, not part of Jesus' personal track: John 9:7 sends
the healed man there. Regional Jerusalem events whose exact setting is unknown
still use a broad city anchor unless an explicitly estimated narrative site is
available. The core's `data/GOSPEL_JOURNEYS.md` records the coverage audit and
uncertainties. Core coordinates are authoritative for event pins; this layer
supplies context, not a second event catalogue.

## The painted city

Under the outlines PlaceMap draws `assets/map/jerusalem_ad30.jpg`, a top-down
painting of the plan fading in from city scale (and dimmed in the dark theme).
`tool/build_jerusalem_image.dart` paints it from the same plan coordinates, so
the outlines lie on what they name, over the Terrain Tiles' heights (SRTM, as
for the relief) shaded from the north-west. The Tyropoeon is cut about 11 m
below its modern fill and the Temple platform levelled. Walls and towers, the
Temple courts and porticoes, Herod's palace, Antonia, the pools and the ways
follow the plan; houses, gardens, olive groves, terraces and tombs are placed
at random for texture and assert nothing.

Recent archaeology the plan and painting now include:

- The **pilgrims' road**: the stepped street from the Siloam pool up the
  Tyropoeon to Robinson's Arch, excavated 2004 to 2019 and dated by coins
  sealed under it to Pilate's governorship
  ([Szanton et al., *Tel Aviv* 46, 2019](https://doi.org/10.1080/03344355.2019.1650491)).
- The **Siloam pool** of the Second Temple period found in 2004, with flights
  of steps on its sides, at the road's foot.
- The **lower aqueduct** from Solomon's Pools, round the south of the western
  hill and up the Tyropoeon to cross into the Temple on **Wilson's Arch**.
- The **Kidron bridge**: the causeway of arches over the Kidron to the Mount
  of Olives in [Mishnah Parah 3:6](https://www.sefaria.org/Mishnah_Parah.3.6),
  labelled as a tradition; no remains of it are identified.

To rebuild the image after changing the plan:

```sh
mkdir -p /tmp/tiles
for t in $(dart run tool/build_jerusalem_image.dart --tiles); do
  curl -sS --fail -o "/tmp/tiles/${t//\//_}.png" \
    "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/$t.png"
done
dart run tool/build_jerusalem_image.dart /tmp/tiles assets/map/jerusalem_ad30.jpg
```
