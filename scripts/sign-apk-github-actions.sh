cd "$( cd "$( dirname "$0"  )" && pwd  )/.."

echo $KEY_FILE_BASE64 > key.jks.base64
base64 -d key.jks.base64 > key.jks

shopt -s nullglob
apks=(build/app/outputs/flutter-apk/*-release.apk)
if [ ${#apks[@]} -eq 0 ]; then
  echo "No release APK found under build/app/outputs/flutter-apk" >&2
  exit 1
fi

for apk in "${apks[@]}"; do
  echo "Signing $apk"
  echo $KEY_PASSWORD | $ANDROID_HOME/build-tools/30.0.2/apksigner sign --ks key.jks "$apk"
done
