#!/bin/bash

BASE_DIR="/srv/www/norayr.am/htdocs/sets/performances"

SPOTLIGHT_FEED="/srv/www/norayr.am/htdocs/sets/spotlight.xml"

SPOTLIGHT_GMI="/srv/www/norayr.am/htdocs/sets/spotlight.gmi"

# spotlight list
SPOTLIGHT_LIST="/srv/www/norayr.am/htdocs/sets/spotlight.txt"

# Temporary file to collect RSS items
SPOTLIGHT_ITEMS=$(mktemp)

STANDARD_WIDTH=800
STANDARD_HEIGHT=800

cat <<EOF > "$SPOTLIGHT_GMI"
# inky's spotlight live sets and performances
=> gemini://norayr.am/sets/index.gmi all sets here

EOF

process_spotlight_episode() {
  EPISODE_DIR="$1"
  echo "Processing directory: $EPISODE_DIR"

  cd "$EPISODE_DIR" || return

  # last image file (case-insensitive)
  IMAGE_FILE=$(ls -1t *.[jJ][pP][gG] *.[pP][nN][gG] 2>/dev/null | head -n 1)
  if [[ -z "$IMAGE_FILE" ]]; then
    echo "no image file found in $EPISODE_DIR. using default image."
    IMAGE_FILE="/srv/www/norayr.am/htdocs/sets/performances/test.jpg"
    IMAGE_URL="/sets/performances/test.jpg"
  else
    # resize
    IMAGE_PATH="$EPISODE_DIR/$IMAGE_FILE"
    DIMENSIONS=$(identify -format "%w %h" "$IMAGE_PATH")
    WIDTH=$(echo "$DIMENSIONS" | awk '{print $1}')
    HEIGHT=$(echo "$DIMENSIONS" | awk '{print $2}')
    if [[ $WIDTH -gt $STANDARD_WIDTH ]] || [[ $HEIGHT -gt $STANDARD_HEIGHT ]]; then
      echo "resizing image $IMAGE_FILE to ${STANDARD_WIDTH}x${STANDARD_HEIGHT}"
      RESIZED_IMAGE_FILE="resized_$IMAGE_FILE"
      convert "$IMAGE_FILE" -resize "${STANDARD_WIDTH}x${STANDARD_HEIGHT}" "$RESIZED_IMAGE_FILE"
      IMAGE_FILE="$RESIZED_IMAGE_FILE"
    fi
    IMAGE_URL="/sets/performances/$(basename "$EPISODE_DIR")/$IMAGE_FILE"
  fi

  # find audio files
  AUDIO_FILE_MP3=$(ls -1t *[0-9a-zA-Z]*_320k.mp3 *.mp3 2>/dev/null | head -n 1)
  AUDIO_FILE_OGG=$(ls -1t *.ogg 2>/dev/null | head -n 1)

  # check if at least one of the audio files exists
  if [[ -z "$AUDIO_FILE_MP3" ]] && [[ -z "$AUDIO_FILE_OGG" ]]; then
    echo "no audio files available in $EPISODE_DIR"
    return
  fi

  # get  metadata for feed
  EPISODE_TITLE=$(basename "$EPISODE_DIR" | sed 's/[-_]/ /g')
  # Extract date from directory name (assuming format YYYY-MM-DD)
  EPISODE_DATE_DIR=$(basename "$EPISODE_DIR" | grep -Eo '^[0-9]{4}-[0-9]{2}-[0-9]{2}')
  if [[ -z "$EPISODE_DATE_DIR" ]]; then
    echo "cannot extract date from directory name: $(basename "$EPISODE_DIR")"
    EPISODE_DATE=$(date -R)
  else
    # set time to 03:00 AM
    EPISODE_DATE="$(date -d "$EPISODE_DATE_DIR 03:00:00" -R)"
  fi
  EPISODE_URL="https://norayr.am/sets/performances/$(basename "$EPISODE_DIR")/"
  EPISODE_GUID="$EPISODE_URL"

  # which audio file to use for the feed
  if [[ -n "$AUDIO_FILE_MP3" ]] && [[ -f "$AUDIO_FILE_MP3" ]]; then
    AUDIO_FILE="$AUDIO_FILE_MP3"
    AUDIO_URL="$EPISODE_URL$(basename "$AUDIO_FILE_MP3")"
    ENCLOSURE_TYPE="audio/mpeg"
  elif [[ -n "$AUDIO_FILE_OGG" ]] && [[ -f "$AUDIO_FILE_OGG" ]]; then
    AUDIO_FILE="$AUDIO_FILE_OGG"
    AUDIO_URL="$EPISODE_URL$(basename "$AUDIO_FILE_OGG")"
    ENCLOSURE_TYPE="audio/ogg"
  else
    echo "No valid audio file found in $EPISODE_DIR"
    return
  fi

  DURATION=$(ffprobe -i "$AUDIO_FILE" -show_entries format=duration -v quiet -of csv="p=0" | \
    awk '{printf("%d:%02d:%02d", $1/3600, ($1%3600)/60, $1%60)}')

  # adding to rss eventually (:
  cat <<EOF >> "$SPOTLIGHT_ITEMS"
    <item>
      <title>$EPISODE_TITLE</title>
      <link>$EPISODE_URL</link>
      <guid isPermaLink="false">$EPISODE_GUID</guid>
      <pubDate>$EPISODE_DATE</pubDate>
      <description><![CDATA[<img src="$IMAGE_URL" alt="Episode Cover" /><br/>You can also listen to the episode <a href="$AUDIO_URL">here</a>.]]></description>
      <enclosure url="$AUDIO_URL" type="$ENCLOSURE_TYPE" />
      <itunes:summary>$EPISODE_TITLE</itunes:summary>
      <itunes:image href="https://norayr.am$IMAGE_URL" />
      <itunes:duration>$DURATION</itunes:duration>
      <itunes:explicit>no</itunes:explicit>
      <category>electronic</category>
    </item>
EOF

  # using ogg if available otherwise mp3
  if [[ -z "$EPISODE_DATE_DIR" ]]; then
    EPISODE_DATE_DIR="Unknown Date"
  fi

  # relative audio path for gemini
  if [[ -n "$AUDIO_FILE_OGG" ]] && [[ -f "$AUDIO_FILE_OGG" ]]; then
    RELATIVE_AUDIO_PATH="performances/$(basename "$EPISODE_DIR")/$(basename "$AUDIO_FILE_OGG")"
  else
    RELATIVE_AUDIO_PATH="performances/$(basename "$EPISODE_DIR")/$(basename "$AUDIO_FILE_MP3")"
  fi

  echo "=> $IMAGE_URL Episode Cover" >> "$SPOTLIGHT_GMI"
  echo "=> $RELATIVE_AUDIO_PATH $EPISODE_DATE_DIR $EPISODE_TITLE" >> "$SPOTLIGHT_GMI"

  cd "$BASE_DIR" || exit
}

# start the spotlight feed
cat <<EOF > "$SPOTLIGHT_FEED"
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
     xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
<channel>
  <title>inky from the tape - Spotlight Sets</title>
  <link>https://norayr.am</link>
  <description><![CDATA[Highlighted live sets and performances by inky. See video recordings <a href="https://toobnix.org/c/tanakian_channel/videos">on toobnix.org</a>]]></description>
  <language>en-us</language>
  <itunes:author>inky from the tape</itunes:author>
  <itunes:summary>Highlighted live sets and performances by inky.</itunes:summary>
  <itunes:owner>
    <itunes:name>inky from the tape</itunes:name>
    <itunes:email>norayr@norayr.am</itunes:email>
  </itunes:owner>
  <itunes:explicit>no</itunes:explicit>
  <itunes:image href="https://norayr.am/sets/performances/test.jpg" />
EOF

# read directories from spotlight.txt
while read -r EPISODE_NAME; do
  # trimming leading and trailing whitespaces
  EPISODE_NAME=$(echo "$EPISODE_NAME" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  echo "Read EPISODE_NAME: '$EPISODE_NAME'"

  # skip empty lines and comments
  if [[ -z "$EPISODE_NAME" || "$EPISODE_NAME" =~ ^# ]]; then
    echo "skipping empty or comment line."
    continue
  fi

  # skipping 'performances' directory
  if [[ "$EPISODE_NAME" == "performances" ]]; then
    echo "skipping directory: $EPISODE_NAME"
    continue
  fi
  EPISODE_DIR="$BASE_DIR/$EPISODE_NAME"
  if [[ -d "$EPISODE_DIR" ]]; then
    process_spotlight_episode "$EPISODE_DIR"
  else
    echo "dir not found: $EPISODE_DIR"
  fi
done < "$SPOTLIGHT_LIST"

# finish the feed
echo "</channel></rss>" >> "$SPOTLIGHT_FEED"

# inserting rss items into the feed
sed -i '/<\/channel>/e cat '"$SPOTLIGHT_ITEMS" "$SPOTLIGHT_FEED"

# cleanup
rm "$SPOTLIGHT_ITEMS"

# copying ready files
cp "$SPOTLIGHT_GMI" /srv/gemini/norayr.am/pub/sets/

echo "yaaaaaaaaaaaaay"
echo "spotlight rss feed generated as $SPOTLIGHT_FEED"
echo "spotlight.gmi  generated as $SPOTLIGHT_GMI"

