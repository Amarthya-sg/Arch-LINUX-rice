// IconResolver.qml
// Self-contained icon resolution logic previously scattered in shell.qml.
//
// Implements the same 8-step cascade as illogical-impulse's guessIcon:
//   1. DesktopEntries.byId(cls)
//   2. Hard substitution map (iconSubstitutions)
//   3. Regex substitution list (iconRegexSubstitutions)
//   4. Exact name exists in icon theme
//   5. Lowercased name
//   6. Reverse-domain last segment
//   7. kebab-normalised class name
//   8. underscore → kebab
//   9. DesktopEntries.heuristicLookup
//  10. Fallback: "application-x-executable"
//
// Public API:
//   guessIconName(cls)       → string (icon name for the theme)
//   iconPathForClass(cls)    → string (absolute icon path via Quickshell.iconPath)
//
// Customisation:
//   Modify iconSubstitutions or iconRegexSubstitutions properties below.
import QtQuick
import Quickshell

QtObject {
    id: root

    // ── Hard substitution map ─────────────────────────────────────────────
    // Add entries here to force a specific icon name for a window class.
    property var iconSubstitutions: ({
        "code-url-handler": "visual-studio-code",
        "Code":             "visual-studio-code",
        "code":             "visual-studio-code",
        "gnome-tweaks":     "org.gnome.tweaks",
        "pavucontrol-qt":   "pavucontrol",
        "footclient":       "foot",
        "kiro":             "kiro",
        "Kiro":             "kiro"
    })

    // ── Regex substitution list ───────────────────────────────────────────
    // Each entry: { regex: /pattern/, replace: "replacement" }
    property var iconRegexSubstitutions: [
        { regex: /^steam_app_(\d+)$/,  replace: "steam_icon_$1"   },
        { regex: /Minecraft.*/,        replace: "minecraft"        },
        { regex: /.*polkit.*/,         replace: "system-lock-screen" },
        { regex: /gcr.prompter/,       replace: "system-lock-screen" }
    ]

    // ── Private helpers ───────────────────────────────────────────────────
    function _iconExists(name) {
        if (!name || name.length === 0) return false
        var p = Quickshell.iconPath(name, true)
        return p.length > 0 && !p.includes("image-missing")
    }
    function _reverseDomainAppName(s) { return s.split(".").slice(-1)[0] }
    function _kebabNorm(s)            { return s.toLowerCase().replace(/\s+/g, "-") }
    function _underscoreKebab(s)      { return s.toLowerCase().replace(/_/g, "-") }

    // ── Public: resolve icon name ─────────────────────────────────────────
    function guessIconName(cls) {
        if (!cls || cls.length === 0) return "application-x-executable"

        // 1. Desktop entries by exact id
        var entry = DesktopEntries.byId(cls)
        if (entry) return entry.icon

        // 2. Hard substitution (exact + lowercase)
        if (iconSubstitutions[cls])               return iconSubstitutions[cls]
        if (iconSubstitutions[cls.toLowerCase()]) return iconSubstitutions[cls.toLowerCase()]

        // 3. Regex substitutions
        for (var i = 0; i < iconRegexSubstitutions.length; i++) {
            var sub = iconRegexSubstitutions[i]
            var r   = cls.replace(sub.regex, sub.replace)
            if (r !== cls) return r
        }

        // 4. Exact name in icon theme
        if (_iconExists(cls))                  return cls

        // 5. Lowercased
        var lower = cls.toLowerCase()
        if (_iconExists(lower))                return lower

        // 6. Reverse-domain last segment
        var dn = _reverseDomainAppName(cls)
        if (_iconExists(dn))                   return dn
        var ldn = dn.toLowerCase()
        if (_iconExists(ldn))                  return ldn

        // 7. kebab-normalised
        if (_iconExists(_kebabNorm(cls)))      return _kebabNorm(cls)

        // 8. underscore → kebab
        if (_iconExists(_underscoreKebab(cls))) return _underscoreKebab(cls)

        // 9. Heuristic desktop entry lookup
        var h = DesktopEntries.heuristicLookup(cls)
        if (h) return h.icon

        // 10. Final fallback
        return "application-x-executable"
    }

    // ── Public: resolve absolute icon path ───────────────────────────────
    function iconPathForClass(cls) {
        return Quickshell.iconPath(guessIconName(cls), true)
    }
}
