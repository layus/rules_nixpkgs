import requests

lat = 37.774929
lng = -122.419418

response = requests.get(f"https://api.sunrise-sunset.org/json?lat={lat}&lng={lng}")

print(response.json())
