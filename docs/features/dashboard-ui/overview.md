# Overview

The current session at a glance. Part of the [Dashboard](../dashboard-ui.md).

![Overview tab](img/overview.png)

## Numbers

- **Profit:** FE earned this session.
- **Per hour:** profit per hour of session time.
- **Session:** session time, with the time it started.
- **Maps:** maps finished, with `+1 running` while you are in a map.
- **Avg map time:** with the fastest map of the session.

## Profit over session

The session's running total, one dot per map. Green dots are profitable maps, red dots lost FE, and the blue dot is the map you are in. Hovering a dot shows the map, its profit and start time; clicking it opens that map in the [Session](session.md) tab.

## Session loot

- **Dropped:** value of everything picked up.
- **Spent:** map costs and consumables.
- **Earned:** the session profit.

Below them, every item dropped this session with its quantity and value, most valuable first. The list scrolls.

## Code

- `src/components/dashboard/OverviewTab.vue`
