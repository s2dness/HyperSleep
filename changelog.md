v2.9

• Fix: fixed Sleep/Freeze apps are no longer re-applied every 30 s once idle (CPU/battery).
• Fix: after the screen turns on, the foreground app is treated as freshly opened (restrictions relax, Auto open counter works).
• Fix: heavy dumpsys window fallback only runs from the main loop while the screen is on.
• "Sleep now" runs as one script (no huge command, errors are reported).
• UI: "Deep" renamed to "Freeze", counter shows opens/threshold, "Show more" for long lists, unsaved-changes pulse on the Save button.
