# Homebrew cask for Skills Manager. Lives in the henrykkim/homebrew-tap repo as
# Casks/skills-manager.rb; copy it there and bump version + sha256 per release.
cask "skills-manager" do
  version "0.4.1"
  sha256 "41b2ee1cb74c379e75a2463eabeb82ded4d8508cb089ef56e922ed631bdc3101"

  url "https://github.com/henrykkim/skills-manager/releases/download/v#{version}/SkillsManager-#{version}.dmg"
  name "Skills Manager"
  desc "Inventory of Claude Code skills and plugins with per-skill cheat sheets"
  homepage "https://github.com/henrykkim/skills-manager"

  # Sparkle updates the app in place; brew shouldn't fight it.
  auto_updates true
  depends_on macos: :sonoma

  app "Skills Manager.app"

  zap trash: [
    "~/Library/Preferences/com.henrykkim.SkillsManager.plist",
  ]
end
