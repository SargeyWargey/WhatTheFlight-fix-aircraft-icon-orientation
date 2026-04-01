## Main Page



I have a attached a mockup of what the app should look like adhere to it the best you can. I want this application to have a simple clean look.

1. The nearest flight to the users location shall have it's flight information displayed in the center of the screen. The information to be displayed:
	1. Flight Number
	2. Origin to Destination
	3. Aircraft type
	4. Altitude in ft
	5. Speed in kts
	6. Distance in miles that represents the miles away from the set geographic location 
	
2. The Setting page shall be accessed by hitting the settings icon in the bottom right of the page.
3. The Plane and helicopter icons around the parameter of the screen represent other aircraft that with the radius set by the user to their set location.
	1. The icon shall face away from the center of the screen if the aircraft is moving away from the set location.
	2. The icon shall face towards the user if the aircraft is moving towards the set location.
	3. The number next to the aircraft represents the mile away from the user the aircraft is.
	4. The aircraft's position on the edge of the screen shall represent the cardinal direction the aircraft is from the user. This will require compass data for ios devices or a user input direction for tvos and mac devices. 
		1. If the user Rotates their phone then the icons and distance indicators shall rotate to always face the direction of the aircraft.
	5. The Plane icon shall represent airplanes and helicopter icon shall represent helicopters.


4. All Speed, Distance, and Knots measurements shall be rounded to the nearest whole number.


5. The application shall determine the size of the screen and have the aircraft icons always be on the parameter of the screen account for for the iphone island time and battery ect, I do not want the icons to be behind those elements. The flight distance indicator next to the airplane icon shall always be posistioned between the aircraft and the center of the screen, but close to the aircraft icon. 

---

I want remove the card functionality. I want the initial aircraft displayed in the center to be the closet aircraft to the set location and I want that aircraft to remain there until it is out  │
│   of range or the user swipes right on the screen. if the user swipes right or the current displayed aircraft is out of range of the radius set then the current closest aircraft shall be          │
│   displayed. 