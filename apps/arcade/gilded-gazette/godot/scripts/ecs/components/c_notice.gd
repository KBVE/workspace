extends ECSComponent
class_name CNotice

## CNotice is one sheet posted on a carriage wall, and which notice it is.
##
## An entity rather than decoration, for the reason a seat is one: a poster can be
## read, and what is read has to be the same fact React opens. The prose is not here
## and never crosses -- both runtimes hold the compiled notice already, so what the
## world needs to know about a poster is which id it carries.

## The shared/data/notices id, which is also what [constant GameEvents.NOTICE_READ]
## sends and what React looks the sheet up by.
var notice_id := &""

## Where the middle of the sheet is, in world space. Held rather than read off the
## view, because [SPointing] asks how near the ray landed to it once per frame and a
## poster does not move.
var at := Vector3.ZERO
