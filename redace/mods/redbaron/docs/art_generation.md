# Campaign art generation record

All 14 assets in `images_required.md` were generated with the built-in image generation tool on
6 November 2026. The prompts below record the selected versions; the required-image spec remains the
art direction reference. No external photographs were used as generation inputs.

Final files: `redace/game_data/language/english/campaigns/redbaron/img/*.png`.
The generator returned 1254 x 1254 squares and 1448 x 1086 page backgrounds. These were converted
to opaque RGB PNG and resized with Pillow's Lanczos filter to 512 x 512 and 2560 x 1920 respectively.
The page backgrounds are upscaled, rather than native 2560 x 1920 generations.

The R.E.8 was regenerated to correct the crew count, the O/100 to place one engine on each side of
the fuselage, and the letter to keep the ribbon black and white. Artwork is stylized game illustration,
not a technical aircraft reference. The epilogue picture (added 11 November 2026) is not generated: it is a Blender/Cycles render, tools/redbaron_epilogue_art.py.

## albatros_d2_photo

Use case: historical-scene. Create one square game briefing photo, 512x512 PNG. Sepia First World War photograph pinned to a pale stained card: an Albatros D.II German biplane fighter in factory finish (pale green and brown camouflage wings, varnished plywood fuselage, black Iron Cross pattée on white squares), three-quarter view from slightly above, flying left to right, propeller blurred; pin hole at top centre, soft vignette, worn paper, no text. Match late-1990s pre-rendered CGI game menu art: softly shaded simple aircraft with convincing two-wing geometry and rigging, warm almost monochrome sepia, isolated on plain cream paper filling the square; entire aircraft visible. No lettering, logos, watermark, modern objects or later symbols. Opaque RGB. Deliver this asset alone.

## red_albatros_photo

Use case: historical-scene. Asset: square 512x512 PNG briefing photo for a WWI flight game. Sepia photograph pinned to pale stained cream card, pin hole at top centre, soft vignette, worn paper. Softly lit late-1990s pre-rendered CGI menu art, warm almost monochrome sepia with faint original paint colors. Single complete aircraft in three-quarter view from slightly above, flying left to right, blurred propeller, plain card background. No lettering, logos, watermark, modern objects or later symbols. Opaque RGB. Subject: Albatros D.III biplane fighter, dull red fuselage and tail, green/brown camouflage wings, black Iron Cross pattée with white borders. Two wings, streamlined plywood fuselage, inline engine.

## red_fokker_photo

Use case: historical-scene. Asset: square 512x512 PNG briefing photo for a WWI flight game. Sepia photograph pinned to pale stained cream card, pin hole at top centre, soft vignette, worn paper. Softly lit late-1990s pre-rendered CGI menu art, warm almost monochrome sepia with faint original paint colors. Single complete aircraft in three-quarter view from slightly above, flying left to right, blurred propeller, plain card background. No lettering, logos, watermark, modern objects or later symbols. Opaque RGB. Subject: Fokker Dr.I triplane, all dull red, black plain straight Latin crosses with white outlines for 1918. Three distinct stacked wings, short nose with rotary engine, blurred propeller.

## dh2_target

Use case: historical-scene. One square 512x512 PNG WWI flight-game briefing target picture. An Airco DH.2 single-seat pusher biplane: small open pilot nacelle at FRONT, engine and blurred propeller BEHIND pilot, open lattice twin tail booms with tailplane at rear, British roundels; three-quarter view. No front tractor propeller. rendered in warm almost monochrome sepia, centered fully inside a pale cream circular disc nearly filling the square, with a thin dark outer ring. Two thin dark diagonal lines cross BEHIND the disc like a gun-sight, only visible at the corners. Dark reddish-brown wood grain fills corners. Soft lighting, late-1990s pre-rendered CGI game menu art. Simple readable silhouette at 128px. Opaque RGB. No text, labels, logos, watermark, modern objects or later symbols.

## bristolscout_target

Use case: historical-scene. One square 512x512 PNG WWI flight-game briefing target picture. A Bristol Scout single-seat biplane, small rotary engine in round cowling with front propeller, British roundels, three-quarter view. rendered in warm almost monochrome sepia, centered fully inside a pale cream circular disc nearly filling the square, with a thin dark outer ring. Two thin dark diagonal lines cross BEHIND the disc like a gun-sight, only visible at the corners. Dark reddish-brown wood grain fills corners. Soft lighting, late-1990s pre-rendered CGI game menu art. Simple readable silhouette at 128px. Opaque RGB. No text, labels, logos, watermark, modern objects or later symbols.

## re8_target

Use case: historical-scene. One square 512x512 PNG WWI flight-game briefing target picture. A Royal Aircraft Factory R.E.8 two-seat biplane with long upper wing, tall fin, observer's ring-mounted Lewis gun behind pilot, British roundels and red-white-blue rudder stripes, three-quarter view. rendered in warm almost monochrome sepia, centered fully inside a pale cream circular disc nearly filling the square, with a thin dark outer ring. Two thin dark diagonal lines cross BEHIND the disc like a gun-sight, only visible at the corners. Dark reddish-brown wood grain fills corners. Soft lighting, late-1990s pre-rendered CGI game menu art. Simple readable silhouette at 128px. Opaque RGB. No text, labels, logos, watermark, modern objects or later symbols.  Critical crew layout: exactly TWO people total, pilot in forward cockpit, single observer in rear cockpit just behind pilot with ring-mounted Lewis gun. Only two cockpit openings, remove third person. R.E.8 has air-cooled RAF 4a engine with cylinders exposed around nose, not a square automobile radiator. Keep target-disc composition.

## balloon_target

Use case: historical-scene. One square 512x512 PNG WWI flight-game briefing target picture. A British Caquot observation balloon: large grey sausage-shaped gas bag with three inflated tail lobes, wicker basket suspended below on rigging, tether cable running down, side view. rendered in warm almost monochrome sepia, centered fully inside a pale cream circular disc nearly filling the square, with a thin dark outer ring. Two thin dark diagonal lines cross BEHIND the disc like a gun-sight, only visible at the corners. Dark reddish-brown wood grain fills corners. Soft lighting, late-1990s pre-rendered CGI game menu art. Simple readable silhouette at 128px. Opaque RGB. No text, labels, logos, watermark, modern objects or later symbols.

## camel_target

Use case: historical-scene. One square 512x512 PNG WWI flight-game briefing target picture. A Sopwith Camel single-seat biplane with rounded rotary-engine cowling and humped twin-machine-gun fairing ahead of cockpit, British roundels, three-quarter view. rendered in warm almost monochrome sepia, centered fully inside a pale cream circular disc nearly filling the square, with a thin dark outer ring. Two thin dark diagonal lines cross BEHIND the disc like a gun-sight, only visible at the corners. Dark reddish-brown wood grain fills corners. Soft lighting, late-1990s pre-rendered CGI game menu art. Simple readable silhouette at 128px. Opaque RGB. No text, labels, logos, watermark, modern objects or later symbols.

## fe2d_target

Use case: historical-scene. One square 512x512 PNG WWI flight-game briefing target picture. A Royal Aircraft Factory F.E.2d TWO-SEAT PUSHER biplane: observer in open FRONT nose with Lewis gun, pilot behind him, engine and blurred propeller BEHIND both crew, open lattice twin tail booms to rear tailplane. British roundels, three-quarter view. No tractor propeller on nose. rendered in warm almost monochrome sepia, centered fully inside a pale cream circular disc nearly filling the square, with a thin dark outer ring. Two thin dark diagonal lines cross BEHIND the disc like a gun-sight, only visible at the corners. Dark reddish-brown wood grain fills corners. Soft lighting, late-1990s pre-rendered CGI game menu art. Simple readable silhouette at 128px. Opaque RGB. No text, labels, logos, watermark, modern objects or later symbols.

## handleypage_target

Use case: historical-scene. One square 512x512 PNG WWI flight-game briefing target picture. A Handley Page O/100 twin-engine biplane bomber, very large wings, exactly two propeller engines between wings, box tail with twin fins, nose and dorsal gun positions, British roundels, three-quarter view from slightly below. rendered in warm almost monochrome sepia, centered fully inside a pale cream circular disc nearly filling the square, with a thin dark outer ring. Two thin dark diagonal lines cross BEHIND the disc like a gun-sight, only visible at the corners. Dark reddish-brown wood grain fills corners. Soft lighting, late-1990s pre-rendered CGI game menu art. Simple readable silhouette at 128px. Opaque RGB. No text, labels, logos, watermark, modern objects or later symbols.  CRITICAL: show FRONT three-quarter view from below with nose in foreground, so both engines are clearly visible symmetrically ONE ON EACH SIDE of the CENTRAL FUSELAGE, one on left wing and one on right wing. Central fuselage runs between engines. Never place both engines on same side. Entire bomber visible.

## tank_target

Use case: historical-scene. One square 512x512 PNG WWI flight-game briefing target picture. A British Mark IV rhomboid tank with tracks running round entire tall rhomboid hull, side gun sponsons, crossing churned mud, three-quarter view; WWI 1917 British landship, no turret. rendered in warm almost monochrome sepia, centered fully inside a pale cream circular disc nearly filling the square, with a thin dark outer ring. Two thin dark diagonal lines cross BEHIND the disc like a gun-sight, only visible at the corners. Dark reddish-brown wood grain fills corners. Soft lighting, late-1990s pre-rendered CGI game menu art. Simple readable silhouette at 128px. Opaque RGB. No text, labels, logos, watermark, modern objects or later symbols.

## intro

Use case: historical-scene. Asset: 4:3 full-page WWI game menu background, 2560x1920 PNG. Dark, low-contrast painted scene for a menu background, warm sepia and deep red: a First World War German airfield at dawn, a row of red Albatros biplanes and Fokker triplanes in front of canvas hangars, mist, lone pilot in leather coat walking towards them. Middle two thirds dark and calm for white text, with aircraft and dawn glow mainly around lower edge and sides. Thin carved wooden frame around edge. Softly lit late-1990s pre-rendered CGI painted menu art, warm amber and sepia, soft focus, gentle bloom. Period accurate 1916-1918. Opaque RGB. No lettering, logos, watermark, modern objects, swastikas or later symbols. No UI, no text; background artwork only.

## complete

Use case: historical-scene. Asset: 4:3 full-page WWI game menu background, 2560x1920 PNG. Painted close-up: a gloved hand holding a Pour le Merite medal, blue enamel Maltese cross with small gold eagles between its arms, suspended from black and white ribbon. Soft window light, warm sepia background of a wooden table and folded leather flying helmet. Place hand and medal at lower right edge and helmet at upper right, keep broad middle two thirds dark and calm for white text. Render enamel unlettered: no text anywhere. Softly lit late-1990s pre-rendered CGI painted menu art, warm amber and sepia, soft focus, gentle bloom. Period accurate 1916-1918. Opaque RGB. No lettering, logos, watermark, modern objects, swastikas or later symbols. No UI, no text; background artwork only.

## letter

Use case: historical-scene. Asset: 4:3 full-page WWI game menu background, 2560x1920 PNG. An aged sheet of writing paper on a dark wooden desk lit by an oil lamp, fountain pen and Iron Cross ribbon beside it. Paper completely blank, broad central writing area spanning x=10%-90%, y=24%-90%; keep it fairly DARK sepia brown with low contrast because game writes white text over it. Lamp, pen, ribbon at outer margins. Solemn subdued atmosphere. Softly lit late-1990s pre-rendered CGI painted menu art, warm amber and sepia, soft focus, gentle bloom. Period accurate 1916-1918. Opaque RGB. No lettering, logos, watermark, modern objects, swastikas or later symbols. No UI, no text; background artwork only. CRITICAL: the Iron Cross ribbon is only a loose strip of BLACK AND WHITE fabric, NO RED on ribbon. No medal or cross pendant attached to ribbon. No awards on desk. Paper dark brown and entirely blank.
