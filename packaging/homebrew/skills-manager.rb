# Homebrew cask for Skills Manager. Lives in the henrykkim/homebrew-tap repo as
# Casks/skills-manager.rb; copy it there and bump version + sha256 per release.
cask "skills-manager" do
  version "0.1.0"
  sha256 "a3058b0e17717320d6c4a76536feb53e252ed049539d4f467c36e0208a5ae514"

  url "https://github.com/henrykkim/skills-manager/releases/download/v#{version}/SkillsManager-#{version}.dmg"
  name "Skills Manager"
  desc "Inventory of Claude Code skills and plugins with per-skill cheat sheets"
  homepage "https://github.com/henrykkim/skills-manager"

  depends_on macos: ">= :sonoma"
  # Sparkle updates the app in place; brew shouldn't fight it.
  auto_updates true

  app "Skills Manager.app"

  zap trash: [
    "~/Library/Preferences/com.henrykkim.SkillsManager.plist",
  ]
end
