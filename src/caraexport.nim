import dom
import ajax
import strutils, sequtils
import jsffi
import json
import times

var JSON {.importc, nodecl.}: JsObject

proc getUsername(token:string):string =
  var request = newXMLHttpRequest()
  let requestURL = "https://web.cara-app.com/api/dashboard/getUserMetadata/"
  request.open("GET", requestURL, false);
  request.setRequestHeader("exporttoken", token)
  request.setRequestHeader("accept", "application/json, text/plain, */*")
  request.send();
  if request.status == 200:
    let json = JSON.parse(request.responseText)
    result = $json["username"].to(cstring)
  else:
    echo "Error download user metadata"

proc getDateRange: tuple[a,b:string] =
  let input_fields = document.querySelectorAll(".jss244 div div input")
  let rawa = $input_fields[0].value
  let rawb = $input_fields[1].value
  let datea = rawa[6 .. ^1] & '-' & rawa[0 .. 1] & '-' & rawa[3 .. 4]
  let dateb = rawb[6 .. ^1] & '-' & rawb[0 .. 1] & '-' & rawb[3 .. 4]
  result.a = $datea
  result.b = $dateb

proc getHealthData(username:string, token:string):JsonNode =
  let (date_start, date_end) = getDateRange()
  var request = newXMLHttpRequest()
  let requestURL = "https://web.cara-app.com//api/dashboard/user/$#/data-points/?start=$#&end=$#&limit=10000&offset=0" % [username, date_start, date_end]
  request.open("GET", requestURL, false);
  request.setRequestHeader("exporttoken", token)
  request.setRequestHeader("accept", "application/json, text/plain, */*")
  request.send();
  if request.status == 200:
    let originalText = $request.responseText
    result = parseJson(originalText)
  else:
    echo "Error download health data"

proc getToken():string =
  let sharelink = $window.location.href
  result = $sharelink.substr( sharelink.rfind('/')+1 )

# ====================

proc datetime(node:JsonNode):DateTime =
  let inputstr = node["timestampTracking"].getStr()
  result = parse( inputstr.substr( 0,inputstr.rfind(':')-1 ) , "yyyy-MM-dd\'T\'HH:mm")

proc toNiceDate(dt:DateTime):string =
  result = dt.format("yyyy-MM-dd")

proc toNiceWeekday(dt:DateTime):string =
  result = dt.format("dddd")

proc toNiceTime(dt:DateTime):string =
  result = dt.format("HH:mm")

proc hasTags(node:JsonNode):bool =
  result = node["tags"].kind != JNull

proc tags(node:JsonNode):seq[string] =
  if node.hasTags:
    result = node["tags"].getStr().split('|')
    
type Record = object
  timestamp:DateTime
  food:seq[string]
  notes:string
  pain, bloating, headache, otherPain, sleep, mood, stress, stool, workout :string
  painTags, bloatingTags, headacheTags, otherPainTags, sleepTags, moodTags, stressTags, stoolTags, workoutTags :seq[string]

proc writeHeaders(file:var string) =
  let data = [ "weekday",
               "date",
               "time",
               "stool",
               "stool tags",
               "food",
               "stomach pain",
               "stomach pain tags",
               "bloating",
               "bloating tags",
               "sleep",
               "sleep tags",
               "headache",
               "headache tags",
               "other pain",
               "other pain tags",
               "stress",
               "stress tags",
               "workout",
               "workout tags",
               "mood",
               "mood tags",
               "notes" ]
  file &= join( data, ", " ) & "\n"

proc writeRecord(file:var string, r:Record) =
  let data = [ r.timestamp.toNiceWeekday,
               r.timestamp.toNiceDate,
               r.timestamp.toNiceTime,
               "\""&r.stool&"\"",
               "\""&join(r.stoolTags,", ")&"\"",
               "\""&join(r.food,", ")&"\"",
               "\""&r.pain&"\"",
               "\""&join(r.painTags,", ")&"\"",
               "\""&r.bloating&"\"",
               "\""&join(r.bloatingTags,", ")&"\"",
               "\""&r.sleep&"\"",
               "\""&join(r.sleepTags,", ")&"\"",
               "\""&r.headache&"\"",
               "\""&join(r.headacheTags,", ")&"\"",
               "\""&r.otherPain&"\"",
               "\""&join(r.otherPainTags,", ")&"\"",
               "\""&r.stress&"\"",
               "\""&join(r.stressTags,", ")&"\"",
               "\""&r.workout&"\"",
               "\""&join(r.workoutTags,", ")&"\"",
               "\""&r.mood&"\"",
               "\""&join(r.moodTags,", ")&"\"",
               "\""&r.notes&"\"" ]
  file &= join( data, ", " ) & "\n"

template makeScaleProc(name:untyped,thing:string):untyped =
  proc `name ScaleString`(node:JsonNode):string =
    result = case node["value"].getInt():
      of 0: "(1/5) I don't have any $#." % [thing]
      of 25: "(2/5) I have mild $#." % [thing]
      of 50: "(3/5) I have moderate $#." % [thing]
      of 75: "(4/5) I have severe $#." % [thing]
      of 100: "(5/5) I have extreme $#." % [thing]
      else: "(error) Unknown $# value '$#'." % [thing, $node["value"].getInt()]

makeScaleProc(pain,"tummy pain")
makeScaleProc(bloating,"bloating")
makeScaleProc(headache,"headache")
makeScaleProc(otherPain,"other pain")
makeScaleProc(stress,"stress")

proc moodScaleString(node:JsonNode):string =
  result = case node["value"].getInt():
    of 0: "(1/5) I feel very good."
    of 25: "(2/5) I feel good."
    of 50: "(3/5) I feel so-so."
    of 75: "(4/5) I don't feel good."
    of 100: "(5/5) I feel awful."
    else: "(error) Unknown $# value '$#'." % ["mood", $node["value"].getInt()]

proc sleepScaleString(node:JsonNode):string =
  result = case node["value"].getInt():
    of 0: "(1/5) I slept for less than 2 hours."
    of 25: "(2/5) I slept for 2 to 4 hours."
    of 50: "(3/5) I slept for 4 to 6 hours."
    of 75: "(4/5) I slept for 6 to 8 hours."
    of 100: "(5/5) I slept for more than 8 hours."
    else: "(error) Unknown $# value '$#'." % ["sleep", $node["value"].getInt()]
    
proc workoutScaleString(node:JsonNode):string =
  result = case node["value"].getInt():
    of 0: "(1/3) I did an easy workout."
    of 50: "(2/3) I did a medium workout."
    of 100: "(3/3) I did a hard workout."
    else: "(error) Unknown $# value '$#'." % ["workout", $node["value"].getInt()]
    
proc stoolScaleString(node:JsonNode):string =
  result = case node["value"].getInt():
    #stool: 0, 14, 28, 42, 57, 71, 85, 100
    of 0: "(1/8) nothing."
    of 14: "(2/8) Separate hard lumps."
    of 28: "(3/8) Lumpy and sausage-like."
    of 42: "(4/8) Sausage shape with cracks in the surface."
    of 57: "(5/8) Perfectly smooth, soft sausage."
    of 71: "(6/8) Soft blobs with clear-cut edges."
    of 85: "(7/8) Mushy consistency with ragged edges."
    of 100: "(8/8) Liquid consistency with no solid pieces."
    else: "(error) Unknown $# value '$#'." % ["stool", $node["value"].getInt()]

template makeRecordProc(name:untyped):untyped =
  proc `record name`(rec:var Record, node:JsonNode) =
    rec.`name` = node.`name ScaleString`
    rec.`name Tags` = concat(rec.`name Tags`, node.tags)

makeRecordProc(sleep)
makeRecordProc(pain)
makeRecordProc(otherPain)
makeRecordProc(bloating)
makeRecordProc(stool)
makeRecordProc(workout)
makeRecordProc(headache)
makeRecordProc(stress)
makeRecordProc(mood)

proc recordFood(rec:var Record, node:JsonNode) =
  for foodNode in node["mealItems"][0]["foodItems"]:
    rec.food.add foodNode["name_en"].getStr()
  for foodNode in node["mealItems"][0]["customFoodItems"]:
    rec.food.add foodNode["name"].getStr()

proc recordNotes(rec:var Record, node:JsonNode) =
  rec.notes = node["text"].getStr()

proc doExport =
  let token = getToken()
  let username = getUsername(token)
  let data = getHealthData(username, token)
  var file = ""
  file.writeHeaders()
  for n in data["results"]:
    var r:Record
    r.timestamp = n.datetime
    case n["type"].getStr():
      of "food": r.recordFood(n)
      of "stool": r.recordStool(n)
      of "sleep": r.recordSleep(n)
      of "pain": r.recordPain(n)
      of "bloating": r.recordBloating(n)
      of "headache": r.recordHeadache(n)
      of "otherPain": r.recordOtherPain(n)
      of "mood": r.recordMood(n)
      of "stress": r.recordStress(n)
      of "workout": r.recordWorkout(n)
      of "notes": r.recordNotes(n)
      else: discard#echo "unknown type-label: '",n["type"].getStr(),"'"
    file.writeRecord(r)
  let downloadable_file = "data:application/octet-stream," & file.encodeURI()
  ## create file download
  var link = document.createElement("a")
  link.setAttribute("download", "health_data.csv")
  link.setAttribute("href", downloadable_file)
  link.click()

## inject the export button
var checkLoadedInterval:ref Interval
proc checkLoaded =
  if document.getElementsByClassName("jss7").len != 0:
    var header = document.getElementsByClassName("jss4")[0]
    var btn_addpatients = document.getElementsByClassName("jss7")[0]
    var btn_export = btn_addpatients.cloneNode(true)
    btn_export.class = "exportbtn"
    header.insertBefore(btn_export, btn_addpatients)
    var btn_export_label = document.querySelector(".exportbtn div button .MuiButton-label")
    btn_export_label.innerHTML = "EXPORT RANGE TO CSV"
    btn_export.onclick = proc(e:Event) =
      doExport()
    window.clearInterval(checkLoadedInterval)

checkLoadedInterval = window.setInterval(checkLoaded, 100)

