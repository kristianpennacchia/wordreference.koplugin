# wordreference.koplugin

Lookup highlighted words or phrases on WordReference directly from KOReader.

<p align="left">
	<img src="https://github.com/user-attachments/assets/37878e48-2bc1-4eb3-9fb6-eaf65e1ef0f5" width=30%>
	<img src="https://github.com/user-attachments/assets/70fc9fcc-af97-4224-825b-0e3b8ca2e897" width=30%>
	<img src="https://github.com/user-attachments/assets/49362e3b-3d60-4f05-971b-ed3fd7b55d28" width=30%>
</p>

[View all available languages](https://github.com/kristianpennacchia/wordreference.koplugin/blob/main/language_pairs.json)

## Install

- Download the [latest release](https://github.com/kristianpennacchia/wordreference.koplugin/releases/latest).
- Unzip `wordreference.koplugin.zip`.
- Copy the `wordreference.koplugin` folder to your KOReader `plugins` directory on the device.
- Restart KOReader.

## Usage

There are multiple ways to lookup phrases on WordReference.

1. Highlight a word or short phrase in a book.
2. Choose "WordReference".
3. A popup shows the definitions from WordReference.

If the `Override Dictionary Quick Lookup` setting is enabled:

1. Short-press a word.
2. A popup shows the definitions from WordReference.

A WordReference button is also available from the dictionary/wikipedia lookup popup.

## Settings

#### Plugin settings

Accessed via Menu → 🔎 → Settings → WordReference settings.

- Override Dictionary Quick Lookup
  - This will override the dictionary quick lookup feature that is enabled with the KOReader setting `Dictionary on single word selection`. If this setting is disabled, then this override will do nothing.
- Include inflections in lookup
  - When looking up a word or phrase, its inflections (if available) will be displayed.
- Auto-Detect languages
  - This will attempt to auto-detect the language of the book and the language used for KOReader, and use this to perform the WordReference lookup.
- Configure languages
  - Pick your desired translation (e.g., it→en, en→it, etc.).
- Check for updates
  - Update this plugin OTA (over-the-air).

---

#### Quick settings

Accessed via the ⚙️ button on the top-left of the WordReference definition popup.

- Font size
  - Change the font size used to display the WordReference definitions.
- Show all settings
  - Shows all of the settings for this plugin.

## Extras

Checkout my other plugin, [Reader Menu Redesign](https://github.com/kristianpennacchia/zzz-readermenuredesign.koplugin), which redesigns some of the reader menus to look prettier.
