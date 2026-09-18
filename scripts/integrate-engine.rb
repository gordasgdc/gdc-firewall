#!/usr/bin/env ruby
# Rescrie ținta „App” a motorului ca ținta GDC Firewall.
#
# Rulat de integrate-engine.sh, NICIODATĂ direct: are nevoie de peticele
# aplicate înainte (consts.h, Info.plist, entitlements). E idempotent —
# se poate rula de câte ori vrei pe același proiect.
require "xcodeproj"

PROJECT   = ARGV[0]
GDC_ROOT  = ARGV[1]          # cale relativă la SOURCE_ROOT, spre sursele GDC
TEAM_ID   = ARGV[2]
APP_ID    = ARGV[3]
VERSION   = ARGV[4]

project = Xcodeproj::Project.open(PROJECT)
app = project.targets.find { |t| t.name == "LuLu" }
ext = project.targets.find { |t| t.name == "Extension" }
abort("Nu găsesc țintele LuLu/Extension — s-a schimbat structura motorului?") unless app && ext

# --- Sursele ------------------------------------------------------------
#
# Din motor păstrăm STRICT trei fișiere partajate: Rule (obiectele pe care
# le întoarce daemon-ul), signing și utilities (de care depinde Rule).
# Restul țintei App — ferestrele, AppDelegate-ul, main.m — dispare: e exact
# interfața pe care o înlocuim. Extension/ și Helper/ nu se ating deloc.
KEEP = ["Shared/Rule.m", "Shared/signing.m", "Shared/utilities.m"]

app.source_build_phase.files.to_a.each do |f|
  path = f.file_ref&.path
  f.remove_from_project unless path && KEEP.include?(path)
end

group = project.main_group.find_subpath("GDC", true)
group.set_source_tree("SOURCE_ROOT")
group.clear

swift_files = Dir.glob(File.join(File.dirname(PROJECT), GDC_ROOT, "**", "*.swift")).sort
abort("Nu am găsit surse Swift în #{GDC_ROOT}") if swift_files.empty?

existing = app.source_build_phase.files.map { |f| f.file_ref&.path }.compact
swift_files.each do |absolute|
  relative = Pathname.new(absolute).relative_path_from(Pathname.new(File.dirname(PROJECT))).to_s
  next if existing.include?(relative)
  ref = group.new_file(relative)
  app.add_file_references([ref])
end

# --- Resursele ----------------------------------------------------------
#
# Ținta App a motorului cară resurse care nu mai au niciun sens după ce i-am
# înlocuit interfața: xib-urile ferestrelor vechi, lista de susținători și
# `Netiquette.app`, o aplicație terță care nici măcar nu există în arhiva
# clonată (build-ul pică pe ea). Păstrăm doar ce folosește codul rămas.
KEEP_RESOURCES = ["Assets.xcassets", "InfoPlist.xcstrings", "Shared/Localizable.xcstrings"]

app.resources_build_phase.files.to_a.each do |f|
  ref = f.file_ref
  name = ref&.path || ref&.display_name
  f.remove_from_project unless name && KEEP_RESOURCES.include?(name)
end

# Dicționarul de procese e o resursă, nu o sursă: fără el, alertele arată
# numele brute ale proceselor în loc de explicațiile în română.
# Glue-ul Obj-C generat (definește globalii pe care îi pierdem odată cu
# App/main.m). Nu poate sta în pachetul SPM: o țintă SPM e monolingvă.
glue = "GDC-EngineGlue.m"
if File.exist?(File.join(File.dirname(PROJECT), glue)) &&
   !app.source_build_phase.files.map { |f| f.file_ref&.path }.include?(glue)
  app.add_file_references([group.new_file(glue)])
end

res = File.join(GDC_ROOT, "Resources/ProcessDictionary.json")
unless app.resources_build_phase.files.map { |f| f.file_ref&.path }.include?(res)
  app.add_resources([group.new_file(res)])
end

# --- Setări de build ----------------------------------------------------

app.build_configurations.each do |config|
  s = config.build_settings
  s["PRODUCT_NAME"] = "GDC Firewall"
  s["PRODUCT_BUNDLE_IDENTIFIER"] = APP_ID
  s["MARKETING_VERSION"] = VERSION
  s["DEVELOPMENT_TEAM"] = TEAM_ID
  s["DEVELOPMENT_TEAM[sdk=macosx*]"] = TEAM_ID
  s["SWIFT_VERSION"] = "5.0"
  # Motorul țintește macOS 10.15; interfața GDC folosește MenuBarExtra și
  # scena Window, ambele macOS 13+.
  s["MACOSX_DEPLOYMENT_TARGET"] = "13.0"
  s["SWIFT_OBJC_BRIDGING_HEADER"] = "GDC-Bridging-Header.h"
  s["SWIFT_OPTIMIZATION_LEVEL"] = config.name == "Debug" ? "-Onone" : "-O"
  # Rule.m / utilities.m includ anteturi din App/ și Shared/ prin nume simplu.
  s["HEADER_SEARCH_PATHS"] = ["$(inherited)", "$(SRCROOT)/App", "$(SRCROOT)/Shared", "$(SRCROOT)/App/3rd-party"]
  # Fără main.m, punctul de intrare e @main-ul SwiftUI.
  s["GENERATE_INFOPLIST_FILE"] = "NO"
end

ext.build_configurations.each do |config|
  s = config.build_settings
  s["PRODUCT_BUNDLE_IDENTIFIER"] = "#{APP_ID}.extension"
  s["MARKETING_VERSION"] = VERSION
  s["DEVELOPMENT_TEAM"] = TEAM_ID
  s["DEVELOPMENT_TEAM[sdk=macosx*]"] = TEAM_ID
  # Xcode 27 refuză orice minim sub 12.0, iar 10.15-ul original al motorului
  # oprește build-ul. Extensia trăiește în pachetul aplicației, deci nu poate
  # rula pe un Mac unde aplicația (13+) nu rulează: îi dăm același minim.
  # Setare de build, nu cod — sursele Extension/ rămân neatinse.
  s["MACOSX_DEPLOYMENT_TARGET"] = "13.0"
end

project.save
puts "  ținta App: #{app.source_build_phase.files.count} surse (#{KEEP.size} din motor, #{swift_files.size} GDC)"
puts "  ținta Extension: neatinsă ca surse, doar identitate de semnare"
