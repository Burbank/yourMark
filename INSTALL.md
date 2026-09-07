# yourMark — install

## 1. Engine

```sh
# uv (recommended)
curl -LsSf https://astral.sh/uv/install.sh | sh
uv tool install 'markitdown[all]'
markitdown --version
```

Homebrew Python also works:

```sh
brew install python
pip3 install -U 'markitdown[all]'
```

Confirm:

```
which markitdown
# typically ~/.local/bin/markitdown on Apple Silicon
```

## 2. App

```sh
git clone git@github.com:Burbank/yourMark.git
cd yourMark
chmod +x Scripts/build-app.sh
./Scripts/build-app.sh
```

That builds a release binary and copies `yourMark.app` to `/Applications`.

## 3. First launch

Gatekeeper may complain (ad-hoc signature). System Settings → Privacy & Security → Open Anyway, or:

```sh
xattr -cr /Applications/yourMark.app
```

## 4. Large 787 PDFs

Convert **per volume**, not a combined 400 MB book. If output is empty, the PDF is likely a scan — reinstall extras:

```sh
uv tool install 'markitdown[all]'
```

OCR still depends on optional MarkItDown plugins; scanned FCOMs may need a separate OCR pass.

## 5. Uninstall

```sh
rm -rf /Applications/yourMark.app
rm -rf ~/Library/Application\ Support/yourMark
# engine is independent
uv tool uninstall markitdown
```
