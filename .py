from spotify_scraper import SpotifyClient


def get_playlist_tracks(playlist_url):
    with SpotifyClient() as client:
        playlist = client.get_playlist(playlist_url, max_tracks=1000)
        tracks = []
        for item in playlist.tracks:
            song = item.track
            artist = song.artists[0].name if song.artists else "unknown"
            tracks.append((song.name, artist))
        return tracks


if __name__ == "__main__":
    url = "https://open.spotify.com/playlist/644n7xdLW4Iv3KfSa5DvA5"
    tracks = get_playlist_tracks(url)

    for name, artist in tracks:
        print(f"{name} - {artist}")

    print(f"\ntotal: {len(tracks)} tracks")