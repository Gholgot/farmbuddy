# FarmBuddy

A World of Warcraft addon that recommends and tracks mount farming runs, scoring each mount by drop rate, time investment, and difficulty.

## Download

- **Landing page:** https://gholgot.github.io/farmbuddy/
- **Direct zip:** https://github.com/Gholgot/farmbuddy/releases/latest/download/FarmBuddy.zip

## Installation

1. Download `FarmBuddy.zip` from the link above.
2. Extract the zip to get a `FarmBuddy/` folder.
3. Move `FarmBuddy/` into your WoW AddOns directory:
   `World of Warcraft/_retail_/Interface/AddOns/`
4. Launch or reload WoW. Type `/farmbuddy` to open.

## Features

- Mount farming recommendations ranked by a composite score
- Scoring based on drop rate, time per run, group requirements, and more
- Weekly lockout tracker across multiple characters
- Session planner to organize your farm list for the day
- Progress tracking broken down by expansion
- Mount search with filters (source, expansion, collected status)
- Achievement-based mount tracking
- WoWHead links for quick reference

## Development

Addon files live in the `FarmBuddy/` directory. A GitHub Actions workflow automatically packages and publishes a new release zip on every push to `main`.
