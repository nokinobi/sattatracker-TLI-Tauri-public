# Session

Every map of the current session, a saved session or all of them. Part of the [Dashboard](../dashboard-ui.md).

![Session tab, Maps](img/session-maps.png)

## Choosing a session

The dropdown offers:

- **Current session**, with its start time.
- **All time**: every recorded map.
- **Saved sessions**, as `name · date time · maps · profit` (without the name when none was given). A session is saved when you start a new one with **Save and start new**.
- **Manage saved sessions…** (see [Cleaning up](#cleaning-up-saved-sessions)).

The right side of the toolbar shows the number of maps, profit, profit per hour and average map time for the selection.

## Maps

The maps of the selection, newest first. Each row has a green or red edge for profit or loss (blue for the running map, marked `LIVE`), the map's start time and duration, item count and cost.

Selecting a map shows:

- **Time**, **Profit** (green or red), **Loot** value (gold) and **Cost** (red when the map cost something).
- The map's net profit over time; hover the chart to read it at any moment. The running map is marked `IN PROGRESS`.
- Its loot, with each item's share of the map's value, and its expenses.

## Loot

Everything dropped in the selection combined: quantity, in how many maps it dropped, its share of all loot and its value.

![Session tab, Loot](img/session-loot.png)

## Deleting a saved session

With a saved session selected, a strip under the toolbar shows `Saved session · N maps · profit FE` and **Delete session**. The first click turns the button red (`Delete N maps?`); the second deletes the session and its maps and switches back to the current session. Clicking elsewhere or choosing another session cancels.

![A saved session selected, with Delete session](img/session-saved.png)

## Cleaning up saved sessions

**Manage saved sessions…** at the end of the dropdown opens a list of all saved sessions with their date, age, maps and profit.

- Tick the sessions to delete, or use **Select older than 30 days** and **Select none**.
- **Delete selected (N)** asks once more (`Delete N sessions?`) and then removes those sessions and their maps from history.
- The current session is never in this list and can't be deleted here.

![Saved sessions dialog](img/session-manage.png)

## Code

- `src/components/dashboard/SessionTab.vue`
- `src/stores/trackerStore.ts`: `deleteSessions` removes sessions and their maps (maps belong to a session by `sessionId`).
