import pg, asyncdispatch

proc main1() =
  # sync version
  let pg = open("", "", "", "host=localhost port=5432 dbname=test")
  let rows = waitFor pg.rows(sql"SELECT ?, pg_sleep(1), 'hi there';", @[$1])
  echo rows

proc main2() {.async.} =
  # run 20 queries at once on a 2 connecton pool
  let pool = newAsyncPool("localhost", "", "", "test", 2)
  var futures = newSeq[Future[seq[Row]]]()
  for i in 0..<20:
    futures.add pool.rows(sql"SELECT ?, pg_sleep(1);", @[$i])
  for f in futures:
    var res = await f
    echo res

main1()
waitFor main2()