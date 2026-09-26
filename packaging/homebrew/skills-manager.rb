# Homebrew cask for Skills Manager. Lives in the henrykkim/homebrew-tap repo as
# Casks/skills-manager.rb; copy it there and bump version + sha256 per release.
cask "skills-manager" do
  version "0.2.1"
  sha256 "16579e3a309f6eb3106de9b562e6766c28c6f8d8935a68e8c16864084b59a757"

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
