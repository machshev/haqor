# Estimated sea courses

`SeaNetwork` supplies offline estimates for ordinary sea legs in the places
and events maps. It uses ORBIS v2's coastal, overseas and ferry geometry from
Elijah Meeks's MIT-licensed repository, revision
`65881112a6e5246d0bf3a90ac22dad7a2728cc2d`. The original licence ships in
`assets/map/orbis-LICENSE.txt`; the app's data-source credits link to ORBIS.

Run `tool/fetch-sea-routes.sh` inside the development shell to rebuild
`assets/map/sea_routes.json`. The script pins the source revision and checksum;
the builder also reads the committed `assets/map/basemap.json`. Changes to that
coastline require rebuilding this network. Source:
https://github.com/emeeks/orbis_v2/blob/65881112a6e5246d0bf3a90ac22dad7a2728cc2d/base_routes.geojson

The builder merges coincident water vertices, rejects edges crossing the
bundled coastline, and adds short, visible connections between nearby vertices.
A local 0.025-degree water grid repairs gaps where ORBIS's coarser geometry
meets land, including narrow straits. These corrections are Haqor estimates.
The output is an undirected distance graph, not ORBIS's seasonal travel-cost
model. It supplies neither sailing times nor claims of an exact historical
course. Coastline checks sample at 500 m and inherit the basemap's resolution.
A port may have up to 5 km of initial land approach because ancient sites and
modern coastlines differ; once a connector reaches water it cannot reenter land.

Every supplied offshore waypoint remains mandatory. If any stretch cannot
connect to the graph within 30 km, or the result is excessively circuitous,
the entire leg retains its supplied geometry. This currently affects some
legs involving Perga, Antioch, Philippi, Ephesus, Samos and Miletus. These need
further harbour/access reconstruction rather than unrestricted inland snapping.
All ordinary sailing legs in the Rome voyage are covered.

The existing core `GetJourneys`/`Journeys` interface supplies journey stops to
both maps. Events are matched by place IDs and passage overlap, and expanded
through the corresponding journey's intervening stops. This preserves the
Rome voyage's Cyprus and Crete waypoints, its stops at Malta, Syracuse and
Rhegium, and the land approach from Puteoli to Rome. No core schema or generated
binding change is needed. Acts 27:14 onward through arrival at Malta (28:1)
retains its supplied storm-drift course; the Exodus crossing also bypasses
ordinary maritime routing. Courses are labelled as estimated in both views.

Tests use the bundled graph and a snapshot of core journey 19's coordinates
and references in `test/fixtures/rome_voyage.json`, captured from the bundled
database. They check water routing, mandatory waypoints, unsupported and
disconnected routes, storm exceptions, event-map expansion and selection, and
retention of land travel at the end of the voyage.
