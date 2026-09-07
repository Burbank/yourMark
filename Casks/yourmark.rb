cask "yourmark" do
  version "0.3.24"
  sha256 :no_check

  url "https://github.com/Burbank/yourMark/releases/latest/download/yourMark.dmg"
  name "yourMark"
  desc "Convert PDFs to Markdown on this Mac"
  homepage "https://burbank.github.io/yourMark/"

  depends_on macos: ">= :sonoma"

  app "yourMark.app"

  caveats <<~EOS
    yourMark uses Microsoft MarkItDown locally. Install the converter once:

      brew install uv
      uv tool install 'markitdown[all]'
  EOS

  zap trash: [
    "~/Library/Application Support/yourMark",
    "~/Library/Preferences/com.burbank.yourmark.plist",
  ]
end
