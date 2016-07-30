_       = require("lodash")
r       = require("request")
rp      = require("request-promise")
tough   = require("tough-cookie")
moment  = require("moment")
Promise = require("bluebird")

Cookie = tough.Cookie
CookieJar = tough.CookieJar

newCookieJar = ->
  j = new CookieJar(undefined, {looseMode: true})

  ## match the same api signature as @request
  {
    _jar: j

    setCookie: (cookieOrStr, uri, options) ->
      j.setCookieSync(cookieOrStr, uri, options)

    getCookieString: (uri) ->
      j.getCookieStringSync(uri)

    getCookies: (uri) ->
      j.getCookiesSync(uri)
  }

flattenCookies = (cookies) ->
  console.log "FLATTEN COOKIES", cookies

  _.reduce cookies, (memo, cookie) ->
    memo[cookie.name] = cookie.value
    memo
  , {}

reduceCookieToArray = (c) ->
  _.reduce c, (memo, val, key) ->
    memo.push [key.trim(), val.trim()].join("=")
    memo
  , []

createCookieString = (c) ->
  reduceCookieToArray(c).join("; ")

module.exports = {
  contentTypeIsJson: (response) ->
    ## TODO: use https://github.com/jshttp/type-is for this
    response?.headers?["content-type"]?.includes("application/json")

  parseJsonBody: (body) ->
    try
      JSON.parse(body)
    catch e
      body

  normalizeResponse: (response) ->
    response = _.pick response, "statusCode", "body", "headers"

    ## normalize status
    response.status = response.statusCode
    delete response.statusCode

    ## if body is a string and content type is json
    ## try to convert the body to JSON
    if _.isString(response.body) and @contentTypeIsJson(response)
      response.body = @parseJsonBody(response.body)

    return response

  setJarCookies: (jar, automation) ->
    setCookie = (cookie) ->
      cookie.name = cookie.key

      ## TODO: handle all these default properties
      ## related to tough cookie store
      cookie.expiry = moment().add(20, "years").unix()

      ## TODO: dont think we need these
      cookie.httpOnly = false
      cookie.secure = false
      cookie.session = false

      return if cookie.name and cookie.name.startsWith("__cypress")

      automation("set:cookie", cookie)

    Promise.try ->
      store = jar.toJSON()

      Promise
      .map(store.cookies, setCookie)

  sendStream: (automation, options = {}) ->
    _.defaults options, {
      headers: {}
      gzip: true
      jar: true
    }

    ## create a new jar instance
    ## unless its falsy or already set
    if options.jar is true
      options.jar = newCookieJar()

    _.extend options, {
      strictSSL: false
      simple: false
      resolveWithFullResponse: true
    }

    setCookies = (cookies) =>
      options.headers["Cookie"] = createCookieString(cookies)

    send = =>
      str = r(options)
      str.getJar = -> options.jar._jar
      str

    automation("get:cookies", {url: options.url})
    .then(flattenCookies)
    .then(setCookies)
    .then(send)

  send: (automation, options = {}) ->
    _.defaults options, {
      headers: {}
      gzip: true
      jar: true
    }

    ## create a new jar instance
    ## unless its falsy or already set
    if options.jar is true
      options.jar = r.jar()

    _.extend options, {
      strictSSL: false
      simple: false
      resolveWithFullResponse: true
    }

    setCookies = (cookies) =>
      options.headers["Cookie"] = createCookieString(cookies)

    send = =>
      ms = Date.now()

      ## dont send in domain
      options = _.omit(options, "domain")

      rp(options)
      .then(@normalizeResponse.bind(@))
      .then (resp) ->
        ## TODO: on response need to set the cookies
        ## on the browser as well!
        resp.duration = Date.now() - ms

        return resp

    if c = options.cookies
      ## if we have a cookie object then just
      ## send the request up!
      if _.isObject(c)
        setCookies(c)
        send()
      else
        ## else go get the cookies first
        ## then make the request

        ## TODO: we can simply use the 'url' property on the cookies API
        ## which automatically pulls all of the cookies that would be
        ## set for that url!
        automation("get:cookies", {url: options.url})
        .then(flattenCookies)
        .then(setCookies)
        .then(send)
    else
      send()

}