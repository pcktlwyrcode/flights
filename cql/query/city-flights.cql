MATCH (a1:Airport)-[]->(ad1:AirportDay)-[]-(f:Flight)-[]-(ad2:AirportDay)<-[]-(a2:Airport)
WHERE a1.city = "Bangkok" and a2.city = "Tokyo"
RETURN *

MATCH (a1:Airport)-[]->(ad1:AirportDay)-[]-(f:Flight)-[]-(ad2:AirportDay)<-[]-(a2:Airport)
WHERE ad1.code =~ ".*20191101" AND a1.city = "Bangkok" and a2.city = "Stockholm"
RETURN *

MATCH (a1:Airport)-[]->(ad1:AirportDay)-[]->(f1:Flight)-[]->(ad2:AirportDay)
<-[]-(a2:Airport)-[]->(ad3:AirportDay)-[]->(f2:Flight)-[]->(ad4:AirportDay)<-[]-(a3:Airport)
WHERE ad1.code =~ ".*20191101" AND a1.city = "Bangkok" and a3.city = "Stockholm"
RETURN *

MATCH p = ((a1:Airport)-[:FLIES_TO*2]->(a2:Airport))
WHERE a1.city = "Bangkok" and a2.city = "Stockholm"
RETURN p

MATCH p = ((a1:Airport)-[:FLIES_TO*1..3]->(a2:Airport))
WHERE a1.city = "Bangkok" and a2.city = "Paris"
WITH (distance(a1.location, a2.location) / 1000) as min, p
WITH [x IN apoc.path.elements(p) | x { .city, .code, .distance }] as routes, min
WITH [x IN routes WHERE x.code IS NOT NULL | x { .code, .city }] as stops, apoc.coll.sum([x IN routes WHERE x.distance IS NOT NULL | x.distance]) as distance, min
WHERE distance < min * 1.1
RETURN stops, SIZE(stops) as stops_count, distance
ORDER by stops_count//, distance ASC
LIMIT 100;

CREATE INDEX ON :Airport(country, city);
CREATE INDEX ON :Airport(code);
CREATE INDEX ON :AirportDay(code);

MATCH (a1:Airport)-[f1:FLIES_TO]->(a2:Airport)
WHERE a1.city = "Bangkok"
AND a2.city = "Stockholm"
WITH a1, a2, f1
MATCH (b1:Airport)-[f2:FLIES_TO]->(b2:Airport)-[f3:FLIES_TO]->(b3:Airport)
WHERE a1 = b1 AND a2 = b3
WITH a1,a2,b1,b2,b3,f1,f2,f3,f1.distance as direct, f2.distance + f3.distance as one_stop
WHERE one_stop - direct <= direct * 0.25
//RETURN f1,f2,f3,direct,one_stop
//AND f2.distance + f3.distance <= f1.distance * 1.25
RETURN a1,a2,b1,b2,b3,f1,f2,f3
LIMIT 100

PROFILE MATCH p = ((a1:Airport { code: "BKK" })-[:FLIES_TO*1..2]->(a2:Airport { code: "SVO"}))
WITH { stops: [x IN nodes(p) | x { .code, .city } ], distance: apoc.coll.sum([x IN relationships(p) | x.distance ]) } as route
RETURN route.stops, SIZE(route.stops) as stops_count, route.distance as distance
ORDER by stops_count, distance ASC
LIMIT 100

MATCH p = ((a1:Airport { code: "BKK" })-[:FLIES_TO*1..2]->(a2:Airport { code: "BCN"}))
WITH { stops: [x IN nodes(p) | x { .code, .city } ], distance: apoc.coll.sum([x IN relationships(p) | x.distance ]) } as route//, (distance(a1.location, a2.location) / 1000) as min
//WHERE route.distance < min * 1.1
RETURN route.stops, SIZE(route.stops) as stops_count, route.distance as distance
ORDER by stops_count, distance ASC
LIMIT 100

PROFILE MATCH p = ((a1:Airport { city: "Bangkok" })-[:FLIES_TO*1..3]->(a2:Airport { city: "Paris" }))
WITH { stops: apoc.coll.pairsMin(nodes(p)), distance: apoc.coll.sum([x IN relationships(p) | x.distance ]) } as route
UNWIND route.stops as stop
MATCH (a:Airport)-[:HAS_DAY]->(ad:AirportDay)-[:IN_FLIGHT]->(f:Flight)-[:OUT_FLIGHT]->(:AirportDay)<-[:HAS_DAY]-(b:Airport)
WHERE a.code = stop[0].code AND b.code = stop[1].code AND ad.code = stop[0].code + "_20191101"
WITH collect(f) as flights, route.distance as distance, stop
WITH { distance: distance, stops: collect({ stop: stop, flights: flights }) } as flights
RETURN flights
ORDER by SIZE(flights.stops) ASC, flights.distance ASC
LIMIT 10
//NO INDEX
//Started streaming 10 records after 118325 ms and completed after 118329 ms.
//INDEX
//Started streaming 10 records after 21201 ms and completed after 21211 ms.

PROFILE MATCH p = ((a1:Airport { city: "Bangkok" })-[:FLIES_TO*1..2]->(a2:Airport { city: "Paris" }))
WITH { stops: apoc.coll.pairsMin(nodes(p)), distance: apoc.coll.sum([x IN relationships(p) | x.distance ]) } as root
WITH root, min(root.distance) as min
WHERE root.distance <= min * 1.5 AND SIZE(apoc.coll.duplicates(root.stops)) = 0
UNWIND root.stops as stop
MATCH (a:Airport)-[:HAS_DAY]->(ad:AirportDay)-[:IN_FLIGHT]->(f:Flight)-[:OUT_FLIGHT]->(bd:AirportDay)<-[:HAS_DAY]-(b:Airport)
WHERE a.code = stop[0].code
AND b.code = stop[1].code
AND ad.code = stop[0].code + "_20191101"
AND bd.code = stop[1].code + "_20191101"
WITH root, stop, collect(distinct f) as flights
WITH root.stops as stops, { stops: SIZE(root.stops), distance: root.distance, route: collect({ stop: stop, flights: flights }) } as result
RETURN result
ORDER BY result.stops ASC, result.distance ASC
LIMIT 100

PROFILE MATCH p = ((:Airport { city: "Bangkok" /* code: "BKK" */ })-[:FLIES_TO*1..2]->(:Airport { city: "Barcelona" /* code: "BCN" */ }))
WITH { stops: apoc.coll.pairsMin(nodes(p)), distance: apoc.coll.sum([x IN relationships(p) | x.distance ]) } as root
//WITH root, min(root.distance) as min
//WHERE root.distance <= min * 1.5 AND SIZE(apoc.coll.duplicates(root.stops)) = 0
UNWIND root.stops as stop
MATCH (a:Airport)-[:HAS_DAY]->(ad:AirportDay)-[in]->(f:Flight)-[out]->(bd:AirportDay)<-[:HAS_DAY]-(b:Airport)
WHERE a.code = stop[0].code AND stop[1].code = stop[1].code
AND type(in) = stop[0].code + "_FLIGHT" AND type(out) = stop[0].code + "_FLIGHT"
AND ad.code = stop[0].code + "_20191101" AND bd.code = stop[1].code + "_20191101"
WITH root, stop, collect(f) as flights
WITH root, collect({ stop: stop, flights: flights }) as route

//RETURN stop, { stops: SIZE(root.stops), distance: root.distance, route: { from: a, to: b, flights: collect(f) } } as result
//RETURN collect({ a: a, b: b }) as result
//ORDER BY result.stops ASC, result.distance ASC
LIMIT 100

//cypher
WITH 7000 * 1.25 as AVG_DISTANCE
MATCH p = ((a:Airport { city: "Bangkok" })-[:FLIES_TO*1..3]->(:Airport { city: "Moscow" }))
WHERE apoc.coll.sum([x IN relationships(p) | x.distance ]) <= AVG_DISTANCE AND SIZE(apoc.coll.duplicates(nodes(p))) = 0
WITH nodes(p) as stops
UNWIND apoc.coll.pairsMin(stops) as stop
MATCH (ad:AirportDay)-[in]->(f:Flight)-[out]->(bd:AirportDay)
WHERE type(in) = stop[0].code + "_FLIGHT" AND type(out) = stop[0].code + "_FLIGHT"
AND ad.code = stop[0].code + "_20191101" AND bd.code = stop[1].code + "_20191101"
WITH stops, stop, collect(distinct f) as flights
RETURN stops as route, { stopsCount: SIZE(stops) - 1, stops: collect({ stop: stop, flights: flights }) } as routeDetails
ORDER BY routeDetails.stopsCount ASC

//apoc.cypher.run
PROFILE WITH { max_distance: 2800, date: "20191101", codeFrom: "SVO", codeTo: "CDG" } as params
CALL apoc.cypher.run("MATCH (ad:AirportDay { code: \"" + params.codeFrom + "_" + params.date  + "\" })-[:" + params.codeFrom + "_FLIGHT" +"]->(f:Flight)-[:" + params.codeFrom + "_FLIGHT" +"]->(bd:AirportDay { code: \"" + params.codeTo + "_" + params.date  + "\" }) RETURN f", {}) yield value
RETURN value

PROFILE WITH { a: "Bangkok", b: "Moscow" } as params
MATCH (a:Airport { city: params.a }), (b:Airport { city: params.b })
WITH distance(point({ latitude: AVG(a.location.latitude), longitude: AVG(a.location.longitude) }),
  point({ latitude: AVG(b.location.latitude), longitude: AVG(b.location.longitude) })) / 1000 as max_distance, params
MATCH p = ((:Airport { city: params.a })-[:FLIES_TO*1..2]->(:Airport { city: params.b }))
WHERE apoc.coll.sum([x IN relationships(p) | x.distance ]) <= max_distance * 1.25 AND SIZE(apoc.coll.duplicates(nodes(p))) = 0
WITH nodes(p) as stops
UNWIND apoc.coll.pairsMin(stops) as stop
CALL apoc.cypher.run("MATCH (ad:AirportDay { code: \"" + stop[0].code + "_20191101\" })-[:" + stop[0].code + "_FLIGHT]->(f:Flight)-[:" + stop[0].code + "_FLIGHT]->(bd:AirportDay { code: \"" + stop[1].code + "_20191101\" }) MATCH (f)-[:OPERATED_BY]->(a:Airline) RETURN f as flight, a as company", {}) yield value
WITH stops, stop, collect(distinct value) as flights
RETURN stops as route, { stopsCount: SIZE(stops) - 1, stops: collect({ stop: stop, flights: flights }) } as routeDetails
ORDER BY routeDetails.stopsCount ASC

PROFILE WITH { a: "Bangkok", b: "Moscow", date: "20200101", atype: "city", btype: "city" } as params
MATCH (a:Airport), (b:Airport)
WHERE ((params.atype = "city" AND a.city = params.a) OR (params.atype = "airport" AND a.code = params.a))
  AND ((params.btype = "city" AND b.city = params.b) OR (params.btype = "airport" AND b.code = params.b))
WITH distance(point({ latitude: AVG(a.location.latitude), longitude: AVG(a.location.longitude) }),
  point({ latitude: AVG(b.location.latitude), longitude: AVG(b.location.longitude) })) / 1000 as max_distance, params
MATCH path = ((a:Airport)-[:FLIES_TO*..3]->(b:Airport))
WHERE ((params.atype = "city" AND a.city = params.a) OR (params.atype = "airport" AND a.code = params.a))
  AND ((params.btype = "city" AND b.city = params.b) OR (params.btype = "airport" AND b.code = params.b))
  AND apoc.coll.sum([x IN relationships(path) | x.distance ]) <= max_distance * 1.25 AND SIZE(apoc.coll.duplicates([ x IN nodes(path) | x.city ])) = 0
WITH nodes(path) as stops, params
UNWIND apoc.coll.pairsMin(stops) as pair
CALL apoc.cypher.run("MATCH (ad:AirportDay { code: \"" + pair[0].code + "_" + params.date + "\" })-[:" + pair[0].code + "_FLIGHT]->(f:Flight)-[:" + pair[0].code + "_FLIGHT]->(bd:AirportDay { code: \"" + pair[1].code + "_" + params.date + "\" }) MATCH (f)-[:OPERATED_BY]->(a:Airline) RETURN f as flight, a as company, $pair as pair, ($pair[0].code + $pair[1].code) as key", { pair: pair }) yield value
WITH stops, pair, collect(distinct value) as flights
WITH stops, SIZE(stops) - 2 as stopsCount, collect({ pair: pair, flights: flights }) as route
WITH apoc.coll.combinations(apoc.coll.flatten([ x IN route | x.flights]), stopsCount + 1, stopsCount + 1) as all_routes, stopsCount
RETURN [ x IN all_routes
WHERE stopsCount = 0
  OR (stopsCount = 1 AND x[0].key <> x[1].key)
  OR (stopsCount = 2 AND x[0].key <> x[1].key AND x[0].key <> x[2].key AND x[1].key <> x[2].key) | x ] as unique_routes, stopsCount
ORDER BY stopsCount ASC


PROFILE WITH { a: "Bangkok", b: "Moscow", date: "20200101", atype: "city", btype: "city" } as params
MATCH (a:Airport), (b:Airport)
WHERE ((params.atype = "city" AND a.city = params.a) OR (params.atype = "airport" AND a.code = params.a))
  AND ((params.btype = "city" AND b.city = params.b) OR (params.btype = "airport" AND b.code = params.b))
WITH distance(point({ latitude: AVG(a.location.latitude), longitude: AVG(a.location.longitude) }),
  point({ latitude: AVG(b.location.latitude), longitude: AVG(b.location.longitude) })) / 1000 as max_distance, params
MATCH path = ((a:Airport)-[:FLIES_TO*..3]->(b:Airport))
WHERE ((params.atype = "city" AND a.city = params.a) OR (params.atype = "airport" AND a.code = params.a))
  AND ((params.btype = "city" AND b.city = params.b) OR (params.btype = "airport" AND b.code = params.b))
  AND apoc.coll.sum([x IN relationships(path) | x.distance ]) <= max_distance * 1.25 AND SIZE(apoc.coll.duplicates([ x IN nodes(path) | x.city ])) = 0
WITH nodes(path) as stops, params
UNWIND apoc.coll.pairsMin(stops) as pair
MATCH (ad:AirportDay { code: pair[0].code + "_" + params.date })-[r1]->(f:Flight)-[r2]->(bd:AirportDay { code: pair[1].code + "_" + params.date })
WHERE type(r1) = pair[0].code + "_FLIGHT" AND type(r2) = pair[0].code + "_FLIGHT"
MATCH (f)-[:OPERATED_BY]->(a:Airline)
RETURN stops, { flight: f, company: a, pair: pair, key: pair[0].code + pair[1].code } as node

PROFILE WITH { a: "Bangkok", b: "New York", date: "20200101", atype: "city", btype: "city" } as params
MATCH (a:Airport), (b:Airport)
WHERE ((params.atype = "city" AND a.city = params.a) OR (params.atype = "airport" AND a.code = params.a))
  AND ((params.btype = "city" AND b.city = params.b) OR (params.btype = "airport" AND b.code = params.b))
WITH distance(point({ latitude: AVG(a.location.latitude), longitude: AVG(a.location.longitude) }),
  point({ latitude: AVG(b.location.latitude), longitude: AVG(b.location.longitude) })) / 1000 as max_distance, params
MATCH path = ((a:Airport)-[:FLIES_TO*..2]->(b:Airport))
WHERE ((params.atype = "city" AND a.city = params.a) OR (params.atype = "airport" AND a.code = params.a))
  AND ((params.btype = "city" AND b.city = params.b) OR (params.btype = "airport" AND b.code = params.b))
  AND apoc.coll.sum([x IN relationships(path) | x.distance ]) <= max_distance * 1.25 AND SIZE(apoc.coll.duplicates([ x IN nodes(path) | x.city ])) = 0
WITH nodes(path) as route, params
MATCH (ad:AirportDay { code: route[0].code + "_" + params.date })-[r1]->(f:Flight)-[r2]->(bd:AirportDay { code: route[1].code + "_" + params.date })
WHERE type(r1) = route[0].code + "_FLIGHT" AND type(r2) = route[0].code + "_FLIGHT"
MATCH (f)-[:OPERATED_BY]->(a:Airline)
WITH collect({ flights: [{ flight: f, company: a }], next: datetime(datetime(f.departs) + duration(f.duration) + duration("PT1H")), route: route }) as flights, params
WITH filter(x IN flights WHERE size(x.route) = 2) as directs, filter(x IN flights WHERE size(x.route) = 3) as singlestopers, params
UNWIND singlestopers as singlestoper
WITH singlestoper, singlestoper.next.year + CASE WHEN singlestoper.next.month > 9 THEN "" ELSE "0" END + singlestoper.next.month + CASE WHEN singlestoper.next.day > 9 THEN "" ELSE "0" END + singlestoper.next.day as date, params, [ x IN directs | { stops: 0, flights: x.flights, route: x.route }] as directs
MATCH (ad:AirportDay { code: singlestoper.route[1].code + "_" + date })-[r1]->(f:Flight)-[r2]->(bd:AirportDay { code: singlestoper.route[2].code + "_" + date })
WHERE type(r1) = singlestoper.route[1].code + "_FLIGHT" AND type(r2) = singlestoper.route[1].code + "_FLIGHT" AND datetime(f.departs) > singlestoper.next
MATCH (f)-[:OPERATED_BY]->(a:Airline)
WITH collect({ stops: 1, flights: apoc.coll.union(singlestoper.flights, [{ flight: f, company: a }]), transfer: duration.between(datetime(singlestoper.next - duration("PT1H")), datetime(f.departs)).minutes, route: singlestoper.route }) as flights, directs
UNWIND apoc.coll.union(directs, flights) as flight
RETURN flight

//city only
PROFILE WITH { a: "Bangkok", b: "New York", date: "20200101" } as params
MATCH (a:Airport), (b:Airport)
WHERE a.city = params.a AND b.city = params.b
WITH distance(point({ latitude: AVG(a.location.latitude), longitude: AVG(a.location.longitude) }),
  point({ latitude: AVG(b.location.latitude), longitude: AVG(b.location.longitude) })) / 1000 as max_distance, params
MATCH path = ((a:Airport)-[:FLIES_TO*..3]->(b:Airport))
WHERE a.city = params.a AND b.city = params.b
  AND apoc.coll.sum([x IN relationships(path) | x.distance ]) <= max_distance * 1.25 AND SIZE(apoc.coll.duplicates([ x IN nodes(path) | x.city ])) = 0
WITH nodes(path) as route, params
MATCH (ad:AirportDay { code: route[0].code + "_" + params.date })-[r1]->(f:Flight)-[r2]->(bd:AirportDay { code: route[1].code + "_" + params.date })
WHERE type(r1) = route[0].code + "_FLIGHT" AND type(r2) = route[0].code + "_FLIGHT"
MATCH (f)-[:OPERATED_BY]->(a:Airline)
WITH collect({ flights: [{ flight: f, company: a }], next: datetime(datetime(f.departs) + duration(f.duration) + duration("PT1H")), route: route }) as flights, params
WITH filter(x IN flights WHERE size(x.route) = 2) as directs, filter(x IN flights WHERE size(x.route) = 3) as singlestopers, params
UNWIND singlestopers as singlestoper
WITH singlestoper, apoc.date.format(datetime({ year: singlestoper.next.year, month: singlestoper.next.month, day: singlestoper.next.day }).epochSeconds, 's', 'yyyyMMdd') as date, params, [ x IN directs | { stops: 0, flights: x.flights, route: x.route }] as directs
MATCH (ad:AirportDay { code: singlestoper.route[1].code + "_" + date })-[r1]->(f:Flight)-[r2]->(bd:AirportDay { code: singlestoper.route[2].code + "_" + date })
WHERE type(r1) = singlestoper.route[1].code + "_FLIGHT" AND type(r2) = singlestoper.route[1].code + "_FLIGHT" AND datetime(f.departs) > singlestoper.next
MATCH (f)-[:OPERATED_BY]->(a:Airline)
WITH collect({ stops: 1, flights: apoc.coll.union(singlestoper.flights, [{ flight: f, company: a }]), transfer: duration.between(datetime(singlestoper.next - duration("PT1H")), datetime(f.departs)).minutes, route: singlestoper.route }) as flights, directs
UNWIND apoc.coll.union(directs, flights) as flight
RETURN flight

//hop0, hop1
PROFILE WITH { a: "Bangkok", b: "New York", date: "20200101" } as params
MATCH (a:Airport), (b:Airport)
WHERE a.city = params.a AND b.city = params.b
WITH distance(point({ latitude: AVG(a.location.latitude), longitude: AVG(a.location.longitude) }),
  point({ latitude: AVG(b.location.latitude), longitude: AVG(b.location.longitude) })) / 1000 as max_distance, params
MATCH path = ((a:Airport)-[:FLIES_TO*..3]->(b:Airport))
WHERE a.city = params.a AND b.city = params.b
  AND apoc.coll.sum([x IN relationships(path) | x.distance ]) <= max_distance * 1.25 AND SIZE(apoc.coll.duplicates([ x IN nodes(path) | x.city ])) = 0
WITH nodes(path) as route, params
MATCH (ad:AirportDay { code: route[0].code + "_" + params.date })-[r1]->(f:Flight)-[r2]->(bd:AirportDay { code: route[1].code + "_" + params.date })
WHERE type(r1) = route[0].code + "_FLIGHT" AND type(r2) = route[0].code + "_FLIGHT"
MATCH (f)-[:OPERATED_BY]->(a:Airline)
WITH collect({ flights: [{ flight: f, company: a }], next: datetime(f.departs) + duration(f.duration) + duration("PT1H"), route: route }) as flights, params
WITH filter(x IN flights WHERE size(x.route) = 2) as listhop0, filter(x IN flights WHERE size(x.route) = 3) as listhop1, filter(x IN flights WHERE size(x.route) = 4) as listhop2, params
UNWIND listhop1 as hop1
MATCH (ad:AirportDay { code: hop1.route[1].code + "_" + apoc.date.format(datetime({ year: hop1.next.year, month: hop1.next.month, day: hop1.next.day }).epochSeconds, 's', 'yyyyMMdd') })-[r1]->(f:Flight)-[r2]->(bd:AirportDay { code: hop1.route[2].code + "_" + apoc.date.format(datetime({ year: hop1.next.year, month: hop1.next.month, day: hop1.next.day }).epochSeconds, 's', 'yyyyMMdd') })
WHERE type(r1) = hop1.route[1].code + "_FLIGHT" AND type(r2) = hop1.route[1].code + "_FLIGHT" AND datetime(f.departs) > hop1.next
MATCH (f)-[:OPERATED_BY]->(a:Airline)
WITH collect({ stops: 1, flights: apoc.coll.union(hop1.flights, [{ flight: f, company: a }]), route: hop1.route, transfer: duration.between(datetime(hop1.next - duration("PT1H")), datetime(f.departs)).minutes }) as listhop1, [ x IN listhop0 | { stops: 0, flights: x.flights, route: x.route }] as listhop0
UNWIND apoc.coll.union(listhop0, listhop1) as flight
RETURN flight

//hop0, hop1, hop2
PROFILE WITH { a: "Bangkok", b: "New York", date: "20200101" } as params
MATCH (a:Airport), (b:Airport)
WHERE a.city = params.a AND b.city = params.b
WITH distance(point({ latitude: AVG(a.location.latitude), longitude: AVG(a.location.longitude) }),
  point({ latitude: AVG(b.location.latitude), longitude: AVG(b.location.longitude) })) / 1000 as max_distance, params
MATCH path = ((a:Airport)-[:FLIES_TO*..3]->(b:Airport))
WHERE a.city = params.a AND b.city = params.b
  AND apoc.coll.sum([x IN relationships(path) | x.distance ]) <= max_distance * 1.25 AND SIZE(apoc.coll.duplicates([ x IN nodes(path) | x.city ])) = 0
WITH nodes(path) as route, params
MATCH (ad:AirportDay { code: route[0].code + "_" + params.date })-[r1]->(f:Flight)-[r2]->(bd:AirportDay { code: route[1].code + "_" + params.date })
WHERE type(r1) = route[0].code + "_FLIGHT" AND type(r2) = route[0].code + "_FLIGHT"
MATCH (f)-[:OPERATED_BY]->(a:Airline)
WITH collect({ flights: [{ flight: f, company: a }], next: datetime(f.departs) + duration(f.duration) + duration("PT1H"), route: route }) as flights, params
WITH filter(x IN flights WHERE size(x.route) = 2) as listhop0, filter(x IN flights WHERE size(x.route) = 3) as listhop1, filter(x IN flights WHERE size(x.route) = 4) as listhop2, params
UNWIND listhop1 as hop1
MATCH (ad:AirportDay { code: hop1.route[1].code + "_" + apoc.date.format(datetime({ year: hop1.next.year, month: hop1.next.month, day: hop1.next.day }).epochSeconds, 's', 'yyyyMMdd') })-[r1]->(f:Flight)-[r2]->(bd:AirportDay { code: hop1.route[2].code + "_" + apoc.date.format(datetime({ year: hop1.next.year, month: hop1.next.month, day: hop1.next.day }).epochSeconds, 's', 'yyyyMMdd') })
WHERE type(r1) = hop1.route[1].code + "_FLIGHT" AND type(r2) = hop1.route[1].code + "_FLIGHT" AND datetime(f.departs) > hop1.next
MATCH (f)-[:OPERATED_BY]->(a:Airline)
WITH listhop2, collect({ stops: 1, flights: apoc.coll.union(hop1.flights, [{ flight: f, company: a, transfer: duration.between(datetime(hop1.next - duration("PT1H")), datetime(f.departs)).minutes }]), route: hop1.route }) as listhop1, [ x IN listhop0 | { stops: 0, flights: x.flights, route: x.route }] as listhop0
WITH listhop2, listhop1, listhop0
UNWIND listhop2 as hop2
MATCH (ad:AirportDay { code: hop2.route[1].code + "_" + apoc.date.format(datetime({ year: hop2.next.year, month: hop2.next.month, day: hop2.next.day }).epochSeconds, 's', 'yyyyMMdd') })-[r1]->(f:Flight)-[r2]->(bd:AirportDay { code: hop2.route[2].code + "_" + apoc.date.format(datetime({ year: hop2.next.year, month: hop2.next.month, day: hop2.next.day }).epochSeconds, 's', 'yyyyMMdd') })
WHERE type(r1) = hop2.route[1].code + "_FLIGHT" AND type(r2) = hop2.route[1].code + "_FLIGHT" AND datetime(f.departs) > hop2.next
MATCH (f)-[:OPERATED_BY]->(a:Airline)
WITH collect({ flights: apoc.coll.union(hop2.flights, [{ flight: f, company: a, transfer: duration.between(datetime(hop2.next - duration("PT1H")), datetime(f.departs)).minutes }]), next: datetime(f.departs) + duration(f.duration) + duration("PT1H"), route: hop2.route }) as listhop2, listhop1, listhop0
UNWIND listhop2 as hop2
MATCH (ad:AirportDay { code: hop2.route[2].code + "_" + apoc.date.format(datetime({ year: hop2.next.year, month: hop2.next.month, day: hop2.next.day }).epochSeconds, 's', 'yyyyMMdd') })-[r1]->(f:Flight)-[r2]->(bd:AirportDay { code: hop2.route[3].code + "_" + apoc.date.format(datetime({ year: hop2.next.year, month: hop2.next.month, day: hop2.next.day }).epochSeconds, 's', 'yyyyMMdd') })
WHERE type(r1) = hop2.route[2].code + "_FLIGHT" AND type(r2) = hop2.route[2].code + "_FLIGHT" AND datetime(f.departs) > hop2.next
MATCH (f)-[:OPERATED_BY]->(a:Airline)
WITH collect({ stops: 2, flights: apoc.coll.union(hop2.flights, [{ flight: f, company: a, transfer: duration.between(datetime(hop2.next - duration("PT1H")), datetime(f.departs)).minutes }]), route: hop2.route }) as listhop2, listhop1, listhop0
UNWIND apoc.coll.union(apoc.coll.union(listhop0, listhop1), listhop2) as flight
RETURN flight.flights, flight.stops
ORDER BY flight.stops
LIMIT 100