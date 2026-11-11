# Changelog

Each TestFlight upload gets a version (tagged `vX.Y.Z` in git) and a build number (the upload time).
The version shows in the app under **Settings → About**.

## 0.5.0
- Calendar Week: today is wider by default; tap anywhere in a day to widen it, double-tap a day to add an event on that day (an entry with no day in it now lands on the day you tapped)
- Meals can have sides, each with its own recipe; the calendar still shows only the main dish
- Meals: press and hold a planned meal for Remove from Plan; keep moving to drag it like before
- Feast-day food: Find a Recipe opens the search inside the app; open a recipe to save it to Recipes, make it that day's dinner, or add it as a side
- Catholic feasts added to the calendar now show at the bottom of the day for the whole household instead of going to Google; "Show every feast on the calendar" puts all of them there
- Header: the rotating daily card is a little bigger and fills the space the family avatars leave; the dinner card is gone from the header (dinner still shows on Week and the slideshow)
- Night clock comes on about 10 seconds after the lights go off, with a built-in darkness level and nothing to set up (tested on the kitchen iPad)
- Settings is simpler: Daily Info and Kitchen Display have their own pages, Google and week start are one Calendar section, status lines show only when something's wrong, and the Ascension choice is gone (always Sunday)

## 0.4.0
- Meals: press and hold a meal to drag it to another day or swap it; recipe suggestions as you type; the week rolls like the Calendar; dinner shows at the bottom of each day on Week
- Adding ingredients to a list starts with nothing ticked
- Daily info near the weather, all optional in Settings: Catholic feast days, coming up, national and world days, today in history, a thought for today
- Catholic days: tap for the story, food ideas, things to do, readings, prayers and indulgences; show them on the calendar or add one to the family calendar
- Feast-day food: Find a Recipe opens a search for the dish, and Plan Dinner puts it on that day's dinner (it asks before replacing anything)
- Slideshow: photos that don't match the screen now show whole over a blurred copy, so nobody loses their head
- Slideshow button in the left bar; choosing photos moved to Settings → Kitchen display

## 0.3.0
- Calendar: Week is now a rolling view with today on the left (5 or 7 days); the Day view is gone
- Week: tap a day's header to widen it; shorter times and tighter cards so titles are readable; a chevron shows when more events are below
- Swipe to change pages on Calendar, Meals and Chores
- Month fits the screen on busy days, with a "+3" for events that don't fit
- The keyboard no longer opens by itself in Add Event and Add Meal
- iPad runs full screen, without the status bar
- Cleaner iPad portrait layouts

## 0.2.0 (build 202611080025)
- Lists use Apple Reminders, including shared lists (e.g. a family Shopping List)
- Recipes: paste a link or Share → CasitaCal from Safari to import photo, ingredients and steps; recipe box; cooking view; photo tiles for dinner
- Night clock also when the room is dark; optional walk-up wake (front camera); waking returns to Calendar/today
- Weather shows the town name
- Family invites: the invite link is verified in iCloud before sharing; Settings shows iCloud sync status and full errors
- Version and build number in Settings → About
- Recipes: **Add to list…** sends the ingredients you tick to a Reminders list (never automatic)
- Tonight's dinner (or tomorrow's, after 8 PM) in the header and on the slideshow
- Settings → About shows when the TestFlight build expires; the header warns 14 days ahead

## 0.1.0 (builds 202611072340, 202611080001, 202611080004)
- First TestFlight builds: calendar, chores, meals, kiosk mode, iCloud sync across your devices
