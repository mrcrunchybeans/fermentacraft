# 🍎 CiderCraft

**CiderCraft** is an open-source Flutter app designed specifically for homebrewers who focus on **cider, mead, and fruit wine**. It combines the power of precision tracking with beautiful design and user-friendly tools. Inspired by Brewfather—but crafted for fruit fermenters—CiderCraft helps you master every batch from recipe design to bottling.

---

## 🎯 Why CiderCraft?

Most brewing software focuses on beer. CiderCraft fills the gap for makers of:
- 🍏 Hard cider
- 🍯 Mead
- 🍓 Fruit wines and blends

It’s built from the ground up with support for:
- Juice/concentrate-based ingredients
- Additive tracking (e.g., pectic enzyme, sulfites, nutrients)
- Advanced gravity, pH, acidity, and SO₂ calculations
- Batch and fermentation chart tracking
- Inventory & planned event management
- Local-first storage with upcoming cloud sync

---

## 🧰 Features At-a-Glance

### 🧪 Recipe Builder
- Ingredients: juice, fruit, sugar, concentrate, honey, etc.
- Additives: pectic enzyme, acid blend, tannin, Campden, etc.
- Yeast: Select from common strains or enter your own
- Fermentation profile builder with multi-stage temperature/duration control
- Tags for organizing recipes (e.g., "sweet", "session", "apple-only")

### 📐 Smart Calculators
- OG, FG, ABV estimator
- pH input with **acidity classification** (malic acid scale)
- SO₂ dosage estimator (Campden or grams, by pH/volume)
- Gravity adjustment (sugar addition or dilution based on target SG)
- Hydrometer temperature correction (°F or °C)
- FSU (Fermentation Speed Units) tracker

### 📊 Fermentation Charting
- Plot SG and temperature data over time
- Visual fermentation stages with annotations
- Color-coded day/date labels and tooltips
- FSU overlay for evaluating fermentation activity

### 🧾 Inventory Management
- Track ingredient amounts, units, cost, expiration
- Categorize by type (e.g., yeast, juice, additive)
- Add notes, cost per unit, and purchase history

### 🧪 Measurement & Batch Tracking
- View and log readings: SG, temperature, notes
- Batch-specific additives, yeast, and events
- Clone recipes into new batches
- Record planned and completed events (racking, bottling, etc.)

### ⚙️ Customization & Settings
- Choose temperature units (°C or °F)
- Choose volume/weight units (oz, ml, gal, grams, etc.)
- Dark mode support
- Persistent settings via Hive
- Planned: pH rounding, advanced inventory toggles, and cloud backup

---

## 🧪 Tools Suite

A standalone **Tools Page** gives you access to cider-specific calculators:

- ✅ ABV Calculator
- ✅ Gravity Adjustment Tool
- ✅ SO₂ Estimator by pH
- ✅ Campden Tablet Converter
- ✅ Acidity Classifier (TA-based)
- ✅ Temperature Converter (°C/°F/K)
- ✅ Unit Converter (volume and weight)
- ✅ Bubble Counter for fermentation activity

---

## 📸 Screenshots

_Coming soon!_ Expect clean, modern UI inspired by the best brewing software, with tabs, collapsible sections, charts, and smart inputs.

---

## 🛠 Installation

### Prerequisites
- Flutter 3.x or later
- Dart SDK
- Hive (handled via `pubspec.yaml`)
- Android Studio / VS Code

### Local Setup

```bash
git clone https://github.com/mrcrunchybeans/cider-craft.git
cd cider-craft
flutter pub get
flutter run
