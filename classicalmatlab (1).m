%% ================================================================
%  hand_safety_detector.m
%  Industrial Hand / Danger-Zone Safety System — Classical IPCV
%
%  Core problem solved here:
%    Skin segmentation detects BOTH hand and face.
%    This script suppresses the face using three independent layers:
%      (1) Spatial proximity  — only blobs near the danger zone survive
%      (2) Geometric shape    — circular/compact blobs (face) are rejected
%      (3) Distance priority  — closest-to-zone blob wins, not largest
%
%  Inputs  : withoutobject.jpeg  (hand NOT in danger zone)
%            withobject.jpeg     (hand IN danger zone)
%  Outputs : 4-panel figure per image + console alert
%% ================================================================
 
clc; clear; close all;
 
%% ────────────────────────────────────────────────────────────────
%%  SECTION A — ALL TUNABLE PARAMETERS  (edit only here)
%% ────────────────────────────────────────────────────────────────
 
% ── Danger zone  [x_left  y_top  width  height]  (pixels) ───────
%    Use MATLAB's impixelinfo / imtool to read exact coordinates.
DANGER_ZONE = [460, 240, 260, 200];
% ── YCbCr skin thresholds (Kovac et al. 2003 / Chai & Ngan 1999) ─
CB_MIN = 77;   CB_MAX = 127;
CR_MIN = 133;  CR_MAX = 173;
Y_MIN  = 40;   Y_MAX  = 230;     % clamp shadows (low) and specular (high)
 
% ── HSV secondary refinement (set USE_HSV=false to disable) ──────
USE_HSV = true;
H_MIN   = 0.00;  H_MAX = 0.11;   % hue  : red-orange skin band
S_MIN   = 0.08;  S_MAX = 0.88;   % sat  : not grey, not fully saturated
V_MIN   = 0.18;                   % val  : reject near-black regions
 
% ── Gaussian pre-filter ──────────────────────────────────────────
GAUSS_SIGMA = 1.5;
GAUSS_SIZE  = 5;
 
% ── Morphological structuring element radii ──────────────────────
SE_CLOSE_R = 13;    % closing  – bridges finger gaps / ring holes
SE_OPEN_R  = 5;     % opening  – strips thin noise filaments
 
% ── Connected-component quality filters ──────────────────────────
MIN_AREA        = 1500;   % px²  – minimum blob area kept
MAX_AREA        = 80000;  % px²  – cap to ignore merged head+body blobs
MIN_EXTENT      = 0.12;   % area/bbox  – rejects ring-shaped artefacts
MAX_SOLIDITY    = 0.92;   % area/convexhull  – rejects compact (face) blobs
MIN_ASPECT      = 0.30;   % short/long side  – rejects extremely elongated noise
                          %   (hand is irregular but not a thin line)
 
% ── Spatial proximity filter (KEY face-suppression layer) ────────
%    Only blobs whose bounding-box centre is within PROXIMITY_MARGIN
%    pixels of the danger-zone bounding box are considered.
%    The face is typically 300–600 px away; the hand is ≤150 px.
PROXIMITY_MARGIN = 180;   % pixels
 
% ── Face-region exclusion mask (optional hard exclusion) ─────────
%    If the face always appears in the upper-left quadrant, set
%    EXCLUDE_FACE_REGION = true and define the rectangle below.
%    This is a belt-and-suspenders layer on top of the filters above.
EXCLUDE_FACE_REGION = false;
FACE_EXCLUDE_RECT   = [0, 0, 200, 220];  % [x y w h] – upper-left crop
 
%% ────────────────────────────────────────────────────────────────
%%  SECTION B — LOAD IMAGES
%% ────────────────────────────────────────────────────────────────
 
img_safe   = safe_imread('withoutobject.jpeg');
img_danger = safe_imread('withobject.jpeg');
 
%% ────────────────────────────────────────────────────────────────
%%  SECTION C — RUN DETECTOR ON BOTH IMAGES
%% ────────────────────────────────────────────────────────────────
 
fprintf('\n=== Industrial Hand Safety Detector ===\n\n');
 
process_image(img_safe, DANGER_ZONE, ...
    CB_MIN, CB_MAX, CR_MIN, CR_MAX, Y_MIN, Y_MAX, ...
    USE_HSV, H_MIN, H_MAX, S_MIN, S_MAX, V_MIN, ...
    SE_CLOSE_R, SE_OPEN_R, GAUSS_SIGMA, GAUSS_SIZE, ...
    MIN_AREA, MAX_AREA, MIN_EXTENT, MAX_SOLIDITY, MIN_ASPECT, ...
    PROXIMITY_MARGIN, EXCLUDE_FACE_REGION, FACE_EXCLUDE_RECT, ...
    'Image A — withoutobject  (expected: SAFE)');
 
process_image(img_danger, DANGER_ZONE, ...
    CB_MIN, CB_MAX, CR_MIN, CR_MAX, Y_MIN, Y_MAX, ...
    USE_HSV, H_MIN, H_MAX, S_MIN, S_MAX, V_MIN, ...
    SE_CLOSE_R, SE_OPEN_R, GAUSS_SIGMA, GAUSS_SIZE, ...
    MIN_AREA, MAX_AREA, MIN_EXTENT, MAX_SOLIDITY, MIN_ASPECT, ...
    PROXIMITY_MARGIN, EXCLUDE_FACE_REGION, FACE_EXCLUDE_RECT, ...
    'Image B — withobject     (expected: HAND IN DANGER ZONE)');
 
 
%% ================================================================
%%  LOCAL FUNCTIONS
%% ================================================================
 
function process_image(img, dz, ...
        cb_min, cb_max, cr_min, cr_max, y_min, y_max, ...
        use_hsv, h_min, h_max, s_min, s_max, v_min, ...
        se_close_r, se_open_r, g_sigma, g_sz, ...
        min_area, max_area, min_extent, max_solidity, min_aspect, ...
        prox_margin, excl_face, face_rect, fig_title)
 
    [imgH, imgW, ~] = size(img);
 
    % ── 1. Gaussian smoothing ─────────────────────────────────────
    %  Reduces JPEG block artefacts and sensor noise before colour ops.
    h_g   = fspecial('gaussian', [g_sz g_sz], g_sigma);
    img_f = imfilter(img, h_g, 'replicate');
 
    % ── 2. YCbCr skin mask ────────────────────────────────────────
    %  Cb/Cr chrominance is stable across illumination changes.
    %  Y bounds suppress cast shadows (low Y) and metal glare (high Y).
    ycbcr = rgb2ycbcr(img_f);
    Y  = double(ycbcr(:,:,1));
    Cb = double(ycbcr(:,:,2));
    Cr = double(ycbcr(:,:,3));
 
    mask_ycbcr = (Cb >= cb_min) & (Cb <= cb_max) & ...
                 (Cr >= cr_min) & (Cr <= cr_max) & ...
                 (Y  >= y_min)  & (Y  <= y_max);
 
    % ── 3. Optional HSV refinement ────────────────────────────────
    %  Intersecting YCbCr with HSV rejects copper-coloured metal,
    %  wooden surfaces, and orange PPE that share Cb/Cr with skin.
    if use_hsv
        hsv      = rgb2hsv(img_f);
        H = hsv(:,:,1);  S = hsv(:,:,2);  V = hsv(:,:,3);
        mask_hsv = (H >= h_min) & (H <= h_max) & ...
                   (S >= s_min) & (S <= s_max) & ...
                   (V >= v_min);
        skin_raw = mask_ycbcr & mask_hsv;
    else
        skin_raw = mask_ycbcr;
    end
 
    % ── 4. Hard face-region exclusion (optional) ──────────────────
    %  Zeroes out a known face rectangle in the mask.
    %  Only use when the face location is predictable across all images.
    if excl_face
        fr = round(face_rect);
        r1 = max(1, fr(2));  r2 = min(imgH, fr(2)+fr(4));
        c1 = max(1, fr(1));  c2 = min(imgW, fr(1)+fr(3));
        skin_raw(r1:r2, c1:c2) = false;
    end
 
    % ── 5. Morphological pipeline ─────────────────────────────────
    %  Order: close → open → fill → area-open
    %
    %  Closing (r=13): dilation then erosion.
    %    Bridges the inter-finger gaps and ring/knuckle holes that
    %    skin thresholding leaves inside the palm.
    se_c     = strel('disk', se_close_r);
    m_closed = imclose(skin_raw, se_c);
 
    %  Opening (r=5): erosion then dilation.
    %    Strips thin filaments and isolated noise pixels that closing
    %    may have created at specular edges on metal.
    se_o     = strel('disk', se_open_r);
    m_opened = imopen(m_closed, se_o);
 
    %  Hole filling: catches internal reflections inside palm.
    m_filled = imfill(m_opened, 'holes');
 
    %  bwareaopen: drops every blob < min_area before regionprops,
    %  keeping the array sparse and the later loop fast.
    m_clean  = bwareaopen(m_filled, min_area);
 
    % ── 6. Connected-component extraction ─────────────────────────
    cc    = bwconncomp(m_clean, 8);
    props = regionprops(cc, 'Area', 'BoundingBox', ...
                            'Extent', 'Solidity', 'Centroid');
 
    % ── 7. Danger-zone geometry (used in filters below) ───────────
    dz_cx = dz(1) + dz(3)/2;   % danger-zone centre x
    dz_cy = dz(2) + dz(4)/2;   % danger-zone centre y
 
    % Axis-aligned proximity box expanded by PROX_MARGIN
    prox_x1 = dz(1) - prox_margin;
    prox_y1 = dz(2) - prox_margin;
    prox_x2 = dz(1) + dz(3) + prox_margin;
    prox_y2 = dz(2) + dz(4) + prox_margin;
 
    % ── 8. Candidate selection — three filter layers ──────────────
    best_bbox = [];
    best_dist = inf;
 
    for k = 1:length(props)
        bb  = props(k).BoundingBox;          % [x y w h]
        cx  = props(k).Centroid(1);
        cy  = props(k).Centroid(2);
        ar  = props(k).Area;
        ext = props(k).Extent;
        sol = props(k).Solidity;
        asp = min(bb(3),bb(4)) / max(bb(3),bb(4));   % ∈ (0,1]; circle ≈ 1
 
        % ── Layer 1: Area bounds ─────────────────────────────────
        %  Reject dust (< min_area, already done by bwareaopen) and
        %  merged head-body blobs that are unrealistically large.
        if ar < min_area || ar > max_area
            continue;
        end
 
        % ── Layer 2: Shape / geometry filters ────────────────────
        %  Extent: hollow or ring-shaped artefacts have low extent.
        if ext < min_extent
            continue;
        end
        %  Solidity: the face has a near-convex silhouette (solidity
        %  close to 1.0). The hand is irregular (lower solidity).
        %  A threshold of 0.92 rejects compact circular blobs.
        if sol > max_solidity
            continue;
        end
        %  Aspect ratio: the hand is never a near-square compact blob
        %  (that is the face). Values < min_aspect mean very elongated
        %  noise (a thin arm stripe); both extremes are rejected.
        if asp < min_aspect
            continue;
        end
 
        % ── Layer 3: Spatial proximity to danger zone ─────────────
        %  Only blobs whose centroid falls inside the proximity box
        %  are considered. This is the primary face-suppression step:
        %  the face is always far from the machine / danger zone.
        if cx < prox_x1 || cx > prox_x2 || cy < prox_y1 || cy > prox_y2
            continue;
        end
 
        % ── Distance priority: prefer closest blob to zone centre ──
        %  Using centroid-to-zone-centre Euclidean distance.
        %  This replaces the naive "pick largest" rule that caused
        %  the face to dominate when it had more skin pixels.
        dist = sqrt((cx - dz_cx)^2 + (cy - dz_cy)^2);
        if dist < best_dist
            best_dist = dist;
            best_bbox = bb;
        end
    end
 
    hand_detected = ~isempty(best_bbox);
 
    % ── 9. Overlap test (axis-aligned SAT) ────────────────────────
    in_danger = false;
    if hand_detected
        in_danger = boxes_overlap(best_bbox, dz);
    end
 
    % ── 10. Four-panel visualisation ──────────────────────────────
    figure('Name', fig_title, 'NumberTitle', 'off', ...
           'Position', [60 60 1280 680]);
 
    %  Panel 1 — original with danger zone marker
    subplot(1,4,1);
    imshow(img); hold on;
    rectangle('Position', dz, 'EdgeColor', 'yellow', ...
              'LineStyle', '--', 'LineWidth', 2);
    title('Original + Danger Zone', 'FontWeight', 'bold');
 
    %  Panel 2 — raw skin mask
    subplot(1,4,2);
    imshow(skin_raw);
    title('Skin mask (YCbCr ∩ HSV)', 'FontWeight', 'bold');
 
    %  Panel 3 — after full morphological pipeline
    subplot(1,4,3);
    % Show all surviving candidates before the distance filter in cyan,
    % and the selected hand blob in white, to aid parameter tuning.
    overlay = repmat(m_clean, [1 1 3]);
    if hand_detected
        % paint selected blob bright white for visibility
        hb = round(best_bbox);
        r1 = max(1,hb(2)); r2 = min(imgH, hb(2)+hb(4));
        c1 = max(1,hb(1)); c2 = min(imgW, hb(1)+hb(3));
        sel_mask = false(imgH, imgW);
        sel_mask(r1:r2, c1:c2) = m_clean(r1:r2, c1:c2);
        overlay(:,:,1) = m_clean | sel_mask;
        overlay(:,:,2) = m_clean & ~sel_mask;
        overlay(:,:,3) = m_clean & ~sel_mask;
    end
    imshow(uint8(overlay * 255));
    title('Morph result (white=selected)', 'FontWeight', 'bold');
 
    %  Panel 4 — final annotated result
    subplot(1,4,4);
    imshow(img); hold on;
 
    if in_danger
        clr  = 'red';
        lbl  = 'HAND IN DANGER ZONE!';
        tclr = [1 0.08 0.08];
    else
        clr  = 'green';
        lbl  = 'SAFE';
        tclr = [0.05 0.9 0.05];
    end
 
    % Dashed danger-zone rectangle
    rectangle('Position', dz, 'EdgeColor', clr, ...
              'LineStyle', '--', 'LineWidth', 2.5);
    text(dz(1)+5, dz(2)-7, 'DANGER ZONE', ...
         'Color', clr, 'FontSize', 9, 'FontWeight', 'bold');
 
    % Solid hand bounding box
    if hand_detected
        rectangle('Position', best_bbox, ...
                  'EdgeColor', clr, 'LineWidth', 2.5);
        text(best_bbox(1)+5, best_bbox(2)-7, 'HAND', ...
             'Color', clr, 'FontSize', 9, 'FontWeight', 'bold');
    end
 
    % Alert banner
    text(6, 22, lbl, 'Color', tclr, 'FontSize', 13, ...
         'FontWeight', 'bold', 'BackgroundColor', 'k');
 
    title(sprintf('Result: %s', lbl), ...
          'Color', tclr, 'FontWeight', 'bold', 'FontSize', 11);
    hold off;
 
    sgtitle(fig_title, 'FontSize', 12, 'FontWeight', 'bold');
 
    % ── Console output ────────────────────────────────────────────
    if in_danger
        fprintf('[ALERT] %-44s | BBox [%.0f %.0f %.0f %.0f]  dist=%.0f\n', ...
                fig_title, best_bbox, best_dist);
    elseif hand_detected
        fprintf('[SAFE]  %-44s | Hand outside zone. BBox [%.0f %.0f %.0f %.0f]  dist=%.0f\n', ...
                fig_title, best_bbox, best_dist);
    else
        fprintf('[SAFE]  %-44s | No hand candidate found near danger zone.\n', ...
                fig_title);
    end
end
 
 
%% ── boxes_overlap ───────────────────────────────────────────────
%  Axis-aligned bounding-box intersection (Separating Axis Theorem).
%  Format: [x_left  y_top  width  height]
function result = boxes_overlap(A, B)
    ax2 = A(1)+A(3);  ay2 = A(2)+A(4);
    bx2 = B(1)+B(3);  by2 = B(2)+B(4);
    result = ~(ax2 < B(1) || bx2 < A(1) || ay2 < B(2) || by2 < A(2));
end
 
 
%% ── safe_imread ─────────────────────────────────────────────────
%  Loads any supported image and returns a uint8 RGB array.
function img = safe_imread(filename)
    if ~isfile(filename)
        error(['File not found: "%s"\n' ...
               'Working directory: %s\n' ...
               'Tip: use >> cd(''folder_with_images'') before running.'], ...
               filename, pwd);
    end
    raw = imread(filename);
    if size(raw,3) == 1,  raw = cat(3,raw,raw,raw); end   % greyscale→RGB
    if size(raw,3) == 4,  raw = raw(:,:,1:3);        end   % RGBA→RGB
    img = im2uint8(raw);
end