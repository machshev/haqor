# Jerusalem around AD 30

The **Jerusalem · AD 30** control appears on place and sequence maps containing
Jerusalem-area pins. It fits the ancient city, enables the historical layer and
allows zooming to individual buildings. Event pins retain their usual selection
behaviour. The information button explains the reconstruction and opens sources.
The layer is opt-in: other periods of the Bible are not silently shown on an
AD 30 city plan.

`lib/src/widgets/jerusalem_map.dart` contains an original schematic reconstruction
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
