# Simple async driver for postgress

import asyncdispatch
include db_postgres
import print


type
  ## db pool
  AsyncPool* = ref object
    conns: seq[DbConn]
    busy: seq[bool]

  ## Excpetion to catch on errors
  PGError* = object of Exception


proc newAsyncPool*(
    connection,
    user,
    password,
    database: string,
    num: int
  ): AsyncPool =
  ## Create a new async pool of num connections.
  result = AsyncPool()
  for i in 0..<num:
    let conn = open(connection, user, password, database)
    assert conn.status == CONNECTION_OK
    result.conns.add conn
    result.busy.add false


proc checkError(db: DbConn) =
  ## Raises a DbError exception.
  var message = pqErrorMessage(db)
  if message.len > 0:
    raise newException(PGError, $message)


proc rows*(
  db: DbConn,
  query: SqlQuery,
  args: seq[string]): Future[seq[Row]] {.async.} =
  ## Runs the SQL getting results.
  assert db.status == CONNECTION_OK
  let success = pqsendQuery(db, dbFormat(query, args))
  if success != 1: dbError(db) # never seen to fail when async
  while true:
    let success = pqconsumeInput(db)
    if success != 1: dbError(db) # never seen to fail when async
    if pqisBusy(db) == 1:
      await sleepAsync(1)
      continue
    var pqresutl = pqgetResult(db)
    if pqresutl == nil:
      # Check if its a real error or just end of results
      db.checkError()
      return
    var cols = pqnfields(pqresutl)
    var row = newRow(cols)
    for i in 0'i32..pqNtuples(pqresutl)-1:
      setRow(pqresutl, row, i, cols)
      result.add row
    pqclear(pqresutl)


proc getFreeConnIdx(pool: AsyncPool): Future[int] {.async.} =
  ## Wait for a free connection and return it.
  while true:
    for conIdx in 0..<pool.conns.len:
      if not pool.busy[conIdx]:
        pool.busy[conIdx] = true
        return conIdx
    await sleepAsync(100)


proc returnConn(pool: AsyncPool, conIdx: int) =
  ## Make the connection as free after using it and getting results.
  pool.busy[conIdx] = false


proc rows*(
    pool: AsyncPool,
    query: SqlQuery,
    args: seq[string]
  ): Future[seq[Row]] {.async.} =
  ## Runs the SQL getting results.
  let conIdx = await pool.getFreeConnIdx()
  result = await rows(pool.conns[conIdx], query, args)
  pool.returnConn(conIdx)


proc exec*(
    pool: AsyncPool,
    query: SqlQuery,
    args: seq[string]
  ) {.async.} =
  ## Runs the SQL without results.
  let conIdx = await pool.getFreeConnIdx()
  discard await rows(pool.conns[conIdx], query, args)
  pool.returnConn(conIdx)


