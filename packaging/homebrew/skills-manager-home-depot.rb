# Homebrew cask for Skills Manager for Home Depot. Lives in the
# henrykkim/homebrew-tap repo as Casks/skills-manager-home-depot.rb; copy it
# there and bump version + sha256 per release (same version as skills-manager).
cask "skills-manager-home-depot" do
  version "0.4.2"
  sha256 "REPLACE_WITH_SHA256_FROM_THE_RELEASE"

  url "https://github.com/henrykkim/skills-manager/releases/download/v#{version}/SkillsManagerHomeDepot-#{version}.dmg"
  name "Skills Manager for Home Depot"
  desc "Skills Manager with a starter set of recommended Claude Code skills and plugins"
  homepage "https://github.com/henrykkim/skills-manager"

  # Sparkle updates the app in place; brew shouldn't fight it.
  auto_updates true
  depends_on macos: :sonoma

  app "Skills Manager for Home Depot.app"

  zap trash: [
    "~/Library/Preferences/com.henrykkim.SkillsManagerHomeDepot.plist",
  ]
end
