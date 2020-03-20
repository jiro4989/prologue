import httpcore
from strutils import toLowerAscii, join


import ../core/dispatch
from ../core/middlewaresbase import switch
from ../core/context import Context, HandlerAsync
from ../core/response import plainTextResponse, resp, setHeader, addHeader
from ../core/basicregex import re, Regex, RegexMatch, match
import ../core/request


const
  AllHttpMethod = @["get", "post", "put", "patch", "options", "delete"]


proc isAllowedOrigin(origin: string, allowAllOrigins: bool,
    allowOrigins: sink seq[string], allowOriginRegex: sink Regex): bool =
  if allowAllOrigins:
    return true

  var m: RegexMatch
  if origin.match(allowOriginRegex, m):
    return true

  return origin in allowOrigins

proc CorsMiddleware*(
  allowOrigins: sink seq[string] = @[],
  allowOriginRegex: sink Regex = re"",
  allowMethods: sink seq[string] = @["get"],
  allowHeaders: sink seq[string] = @[],
  exposeHeaders: sink seq[string] = @[],
  allowCredentials = false,
  maxAge = 7200,
  excludeEndPoint: seq[string] = @[]
  ): HandlerAsync =

  result = proc(ctx: Context) {.async.} =
    # just for example
    if ctx.request.path in excludeEndPoint:
      await switch(ctx)
      return

    var
      reqHeaders = ctx.request.headers # request headers

    let
      origin = reqHeaders.getOrDefault("origin")
      hasCookie = reqHeaders.hasKey("cookie")

    # don't have origin, switch
    if origin.len == 0:
      await switch(ctx)
      return

    let
      allowAllHeaders = "*" in allowHeaders # allow all headers
      allowAllOrigins = "*" in allowOrigins # allow all origins

    var
      allowMethodsSeq: seq[string] # sequence of allowed methods

    if "*" in allowMethods:
      allowMethodsSeq = AllHttpMethod

    for httpMethod in allowMethods:
      let value = toLowerAscii(httpMethod)
      if value in AllHttpMethod:
        allowMethodsSeq.add value

    # preflight headers
    # This header is necessary as the preflight request is always an OPTIONS and
    # doesn't use the same method as the actual request.
    if ctx.request.reqMethod == HttpOptions and reqHeaders.hasKey("Access-Control-Request-Method"):
      var
        preflightHeaders = newHttpHeaders()
        errorMsg: seq[string] = @[]

      let
        accessControlRequestMethod = reqHeaders["Access-Control-Request-Method"]
        accessControlRequestHeaders = seq[string](reqHeaders.getOrDefault("Access-Control-Request-Headers"))

      if "*" in allowOrigins:
        preflightHeaders["Access-Control-Allow-Origin"] = "*"

      if allowCredentials:
        preflightHeaders["Access-Control-Allow-Credentials"] = "true"

      if exposeHeaders.len != 0:
        preflightHeaders["Access-Control-Expose-Headers"] = exposeHeaders

      if allowAllOrigins:
        if hasCookie:
          preflightHeaders["Access-Control-Allow-Origin"] = origin
      elif not allowAllOrigins and isAllowedOrigin(origin, allowAllOrigins,
          allowOrigins, allowOriginRegex):
        preflightHeaders["Access-Control-Allow-Origin"] = origin
        preflightHeaders.add("vary", "Origin")
      else:
        errorMsg.add "origin"

      preflightHeaders["Access-Control-Allow-Methods"] = allowMethodsSeq
      preflightHeaders["Access-Control-Max-Age"] = $maxAge

      if accessControlRequestMethod notin allowMethodsSeq:
        errorMsg.add "method"

      if allowAllHeaders:
        preflightHeaders["Access-Control-Allow-Headers"] = accessControlRequestHeaders
      else:
        for header in accessControlRequestHeaders:
          if header notin allowHeaders:
            errorMsg.add "headers"
        preflightHeaders["Access-Control-Allow-Headers"] = accessControlRequestHeaders

      if errorMsg.len != 0:
        resp plainTextResponse("Disallowed CORS " &
            errorMsg.join(", "), Http403, preflightHeaders)
      else:
        resp plainTextResponse("Ok", Http200,
            preflightHeaders)
      return

    # simple headers
    await switch(ctx)

    if "*" in allowOrigins:
      ctx.response.setHeader("Access-Control-Allow-Origin", "*")

    if allowCredentials:
      ctx.response.setHeader("Access-Control-Allow-Credentials", "true")

    if exposeHeaders.len != 0:
      ctx.response.setHeader("Access-Control-Expose-Headers", exposeHeaders)

    if allowAllOrigins and hasCookie:
      ctx.response.setHeader("Access-Control-Allow-Origin", origin)
    elif not allowAllOrigins and isAllowedOrigin(origin, allowAllOrigins,
        allowOrigins, allowOriginRegex):
      ctx.response.setHeader("Access-Control-Allow-Origin", origin)
      ctx.response.addHeader("vary", "Origin")
