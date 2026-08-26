# Specification de la camera de course du vaisseau (portage Godot)

## 1. Objet

Ce document specifie le comportement de la camera de poursuite ("chase camera") du vaisseau, tel qu implemente dans wipeout-rewrite (C), et son portage dans le projet Godot.

Portee:

- algorithme de la camera de course externe (camera_update_race_external);
- portage de cet algorithme dans godot/src/scripts/wipeout_ship.gd;
- correspondance entre les grandeurs de l implementation source et celles du portage.

Hors portee:

- camera cockpit interne (camera_update_race_internal): position/angle uniquement, non couplee a un ressort;
- camera d intro (camera_update_race_intro);
- cameras d attract mode (camera_update_attract_circle, camera_update_attract_internal, camera_update_static_follow, camera_update_attract_random);
- camera de rescue droide (camera_update_rescue);
- effet de secousse (camera_update_shake / camera_set_shake).

Ces modes existent dans la reference C mais n ont pas d equivalent dans le portage Godot actuel; ils restent a specifier/implementer ulterieurement si besoin.

## 2. References implementation

- src/wipeout/camera.c
- src/wipeout/camera.h
- src/wipeout/ship.c (ship_cockpit, ship->mat)
- src/types.c (vec3_project_to_ray)
- src/wipeout/track.c (track_nearest_section)
- godot/src/scripts/wipeout_ship.gd
- godot/src/scripts/track_center_line.gd
- godot/tools/psx_track/psx_track_common.py (DEFAULT_UNITS_PER_METER)

## 3. Algorithme source: camera_update_race_external

Entrees: ship->mat (matrice yaw/pitch/roll du vaisseau), ship->angle, camera->section (derniere section connue), camera->velocity (etat persistant).

Etapes par frame:

1. Position brute derriere le vaisseau:
   - pos = vec3_transform(vec3(0, 0, -1024), ship->mat)
   - pos.y -= 200
2. Recalage sur la piste:
   - camera->section = track_nearest_section(pos, vec3(1,1,1), camera->section, NULL)
   - next = camera->section->next
   - target = vec3_project_to_ray(pos, next->center, camera->section->center)
3. Ressort/amortisseur sur l ecart au rail:
   - diff_from_center = pos - target
   - acc = diff_from_center; acc.y += length(diff_from_center) * 0.5
   - camera->velocity -= acc * (0.015625 * 30 * dt)
   - camera->velocity -= camera->velocity * (0.125 * 30 * dt)
   - pos += camera->velocity
4. Affectation finale:
   - camera->position = pos
   - camera->angle = vec3(ship->angle.x, ship->angle.y, 0)  (pitch/yaw du vaisseau, roll force a 0)

Points cles:

- la position de la camera est amortie/retardee (ressort), independamment de l orientation;
- l orientation de la camera suit instantanement le pitch/yaw du vaisseau, sans jamais suivre son roll (l horizon ne penche pas avec le vaisseau);
- track_nearest_section limite sa recherche a une fenetre autour de la section precedente (TRACK_SEARCH_LOOK_BACK/AHEAD), pour eviter un accrochage sur une section proche dans l espace mais eloignee dans la progression (ex: epingle).

## 4. Portage Godot

Fichier: godot/src/scripts/wipeout_ship.gd.

### 4.1 Correspondance des grandeurs

| C (camera.c)                       | Godot (wipeout_ship.gd)                          |
|-------------------------------------|---------------------------------------------------|
| vec3(0,0,-1024) local offset        | Vector3(0, 0, camera_distance) via basis rollee    |
| pos.y -= 200                        | + Vector3.UP * camera_height                       |
| camera->section / track_nearest_section | Curve3D.get_closest_offset sur center_line (recherche globale, non fenetree) |
| next->center                        | point echantillonne a offset + camera_track_probe  |
| camera->section->center             | point echantillonne a offset courant               |
| vec3_project_to_ray                 | projection manuelle sur le segment p_current -> p_ahead |
| 0.015625 * 30                       | camera_spring_accel = 0.46875                      |
| 0.125 * 30                          | camera_spring_damping = 3.75                       |
| camera->velocity                    | camera_velocity                                     |
| camera->angle = (ship.angle.x, ship.angle.y, 0) | _camera_orientation_basis(-global_transform.basis.z) |

### 4.2 Invariance d echelle des constantes de ressort

Les constantes 0.015625*30 et 0.125*30 sont un taux (1/temps), applique multiplicativement a un ecart de position puis reinjecte directement dans la position. Une conversion uniforme d unites (metres Godot vs unites brutes PSX, facteur ~106.5, voir DEFAULT_UNITS_PER_METER) s annule dans ce calcul: les memes constantes numeriques sont donc reutilisees telles quelles en metres, sans reconversion.

### 4.3 Adaptations

- rotation de la matrice du vaisseau par visual_roll autour de l axe avant, pour que la position brute penche avec le roll visuel (equivalent du roll deja present dans ship->mat en C, mais qui en Godot n existe que sur le mesh visuel et pas sur le transform racine);
- recherche de la section la plus proche non fenetree (Curve3D.get_closest_offset sur toute la courbe), par coherence avec le reste du portage (_rescue_to_track utilise deja cette meme approche non fenetree);
- repli (fallback): si center_line est absent ou invalide, la position brute est suivie par un simple lerp (camera_follow_speed), sans ressort;
- camera_velocity est remise a zero lors d un reset/rescue du vaisseau (_reset_dynamic_state) et lors du snap initial (_snap_camera_to_ship), pour eviter qu un ressort charge avant une teleportation ne fasse partir la camera en vol.

### 4.4 Fonctions ajoutees

- _camera_chase_position(delta): calcule et renvoie la position ressort-amortie de la camera pour la frame courante.
- _camera_orientation_basis(forward): construit une base orthonormee a partir du seul vecteur avant (pitch/yaw), sans roll.
- _update_camera(delta): applique position et orientation au CameraRig chaque frame physique, pour un vaisseau controle par le joueur.

## 5. Non couvert par ce portage

- vue cockpit interne (position = ship_cockpit, angle avec roll partiel via save.internal_roll);
- transition automatique intro -> vue interne;
- modes attract (spectateur hors course);
- camera de secours sur le droide de rescue;
- secousse de camera (impacts d armes, chocs).
