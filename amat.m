function mat = amat(img,scales,ws,vistop)

if nargin < 2, scales = 40; end
if nargin < 3, ws = 1e-3; end
if nargin < 4, vistop = false; end
if isscalar(scales)
    R = scales;
    scales = 1:R;
elseif isvector(scales)
    R = numel(scales);
else
    error('''scales'' must be a vector of disk radii or a scalar (#scales)')
end

% Construct disk-shaped filters
filters = cell(1,R); for r=1:R, filters{r} = double(disk(scales(r))); end

% Convert to CIE La*b* color space
img = rgb2labNormalized(im2double(img));

% Compute encodings f(D_I(x,y,r)) at every point (mean values in this case)
enc = imageEncoding(img,filters,'average'); 

% Compute disk cost based on image reconstruction heuristic
diskCost = reconstructionCost(img,enc,filters,scales);

% Compute reedy approximation of the weighted set cover for the AMAT.
profile on;
mat = setCover(img,enc,diskCost,filters,scales,ws,vistop);
profile off; profile viewer;
end

% -------------------------------------------------------------------------
function mat = setCover(img,enc,diskCost,filters,scales,ws,vistop)
% -------------------------------------------------------------------------
% Greedy approximation of the weighted set cover problem.
% -------------------------------------------------------------------------
% Disk cost: refers to the cost contributed to the total absolute cost of 
% placing the disk in the image.
% -------------------------------------------------------------------------
% Disk cost effective: refers to the "normalized" cost of the disk, divided
% by the number of *new* pixels it covers when it is added in the solution.
% -------------------------------------------------------------------------
% numNewPixelsCovered: number of NEW pixels that would be covered by each
% disk if it were to be added in the solution. This number can be easily 
% computed using convolutions, while taking into account the fact that 
% some disks exceed image boundaries.
% -------------------------------------------------------------------------

% Initializations
[H,W,C,R]          = size(enc);
mat.input          = reshape(img, H*W, C);
mat.reconstruction = reshape(mat.input, H*W, C);
mat.axis           = zeros(H,W,C);
mat.radius         = zeros(H,W);
mat.depth          = zeros(H,W); % #disks points(x,y) is covered by
mat.price          = zeros(H,W); % error contributed by each point
mat.se             = zeros(H,W); % squared error at each point
mat.covered        = false(H,W); 
% Flag corners that are not accessible by our filter set
mat.covered([1,end],1)   = true;
mat.covered(end,[1,end]) = true;
mat.ws = ws; % weight for scale-dependent cost term.

% Compute how many pixels are covered be each r-disk.
numNewPixelsCovered = ones(H,W,R);
for r=1:R
    numNewPixelsCovered(:,:,r) = ...
        conv2(numNewPixelsCovered(:,:,r), filters{r},'same');
end

% Add scale-dependent cost term to favor the selection of larger disks.
effectiveCost = @(x,y) bsxfun(@plus, x./y, reshape(ws./scales,1,1,[])); 
diskCostEffective = effectiveCost(diskCost,numNewPixelsCovered);

[x,y] = meshgrid(1:W,1:H);
while ~all(mat.covered(:))
% for i=1:1000
    % Find the most cost-effective disk at the current iteration
    [minCost, indMin] = min(diskCostEffective(:));
    if isinf(minCost), break; end
        
    [yc,xc,rc] = ind2sub([H,W,R], indMin);
    distFromCenterSquared = (x-xc).^2 + (y-yc).^2;
    D = distFromCenterSquared <= scales(rc)^2;   % points covered by the selected disk
    newPixelsCovered  = D & ~mat.covered;        % NEW pixels that are covered by D
    
    % Update MAT
    mat = updateMAT(mat);
    if ~any(newPixelsCovered(:)), break; end
    
    % Update disk costs
    [diskCost,numNewPixelsCovered] = ...
        updateDiskCosts(diskCost,filters,numNewPixelsCovered,newPixelsCovered);
    
    % diskCost for disks that have been completely covered (e.g. the 
    % currently selected disk) will be set to inf or nan, because of the
    % division with numNewPixelsCovered which will be 0 for those disks.
    diskCostEffective = effectiveCost(diskCost,numNewPixelsCovered);
    diskCostEffective(numNewPixelsCovered == 0) = inf;
    assert(allvec(numNewPixelsCovered(yc,xc, 1:rc)==0))
    
    if vistop, visualizeProgress(mat,diskCostEffective); end
    fprintf('%d new pixels covered, %d pixels remaining\n',...
        nnz(newPixelsCovered),nnz(~mat.covered))
end

% Visualize results
mat.reconstruction = reshape(mat.reconstruction,H,W,C);
mat.input = reshape(mat.input,H,W,C);
mat.visualize = @()visualize(mat);

% -------------------------------------------------------------------------
function mat = updateMAT(mat)
% -------------------------------------------------------------------------
reconstructedDisk = ...
    repmat(reshape(enc(yc,xc,:,rc),[1 C]), [nnz(newPixelsCovered),1]);
mat.se(newPixelsCovered) = sum(( ...
    mat.reconstruction(newPixelsCovered,:) - reconstructedDisk ).^2,2);
mat.price(newPixelsCovered) = minCost / nnz(newPixelsCovered);
mat.covered(D) = true;
mat.depth(D) = mat.depth(D) + 1;
mat.reconstruction(newPixelsCovered,:) = reconstructedDisk;
mat.axis(yc,xc,:) = enc(yc,xc,:,rc);
mat.radius(yc,xc) = scales(rc);
end

% -------------------------------------------------------------------------
function [diskCost,numNewPixelsCovered] = ...
        updateDiskCosts(diskCost,filters,numNewPixelsCovered,newPixelsCovered)
% -------------------------------------------------------------------------
% Find how many of the newPixelsCovered are covered by other disks in
% the image and subtract the respective counts from those disks.
[yy,xx] = find(newPixelsCovered);
xmin = min(xx); xmax = max(xx);
ymin = min(yy); ymax = max(yy);
newPixelsCovered = double(newPixelsCovered);
costPerPixel = diskCost ./ numNewPixelsCovered;
for r=1:R
    scale = scales(r);
    xxmin = max(xmin-scale,1); yymin = max(ymin-scale,1);
    xxmax = min(xmax+scale,W); yymax = min(ymax+scale,H);
    numPixelsSubtracted = ...
        conv2(newPixelsCovered(yymin:yymax,xxmin:xxmax),filters{r},'same');
    numNewPixelsCovered(yymin:yymax,xxmin:xxmax, r) = ...
        numNewPixelsCovered(yymin:yymax,xxmin:xxmax, r) - numPixelsSubtracted;
    diskCost(yymin:yymax,xxmin:xxmax, r) = ...
        diskCost(yymin:yymax,xxmin:xxmax, r) - ...
        numPixelsSubtracted .* costPerPixel(yymin:yymax,xxmin:xxmax, r);
end
% Some pixels are assigned NaN values because of the inf-inf subtraction 
% and since max(0,NaN) = 0, we have to reset them explicitly to inf.
diskCost(isnan(diskCost)) = inf;
end

% -------------------------------------------------------------------------
function visualizeProgress(mat,diskCost)
% -------------------------------------------------------------------------
% Sort costs in ascending order to visualize updated top disks.
[~, indSorted] = sort(diskCost(:),'ascend');
[yy,xx,rr] = ind2sub([H,W,R], indSorted(1:vistop));
subplot(221); imshow(reshape(mat.input, H,W,[]));
viscircles([xc,yc],rc, 'Color','k','EnhanceVisibility',false); title('Selected disk');
subplot(222); imshow(bsxfun(@times, reshape(mat.input,H,W,[]), double(~mat.covered)));
viscircles([xx,yy],rr,'Color','w','EnhanceVisibility',false,'Linewidth',0.5);
viscircles([xx(1),yy(1)],rr(1),'Color','b','EnhanceVisibility',false);
viscircles([xc,yc],rc,'Color','y','EnhanceVisibility',false);
title(sprintf('K: covered %d/%d, W: Top-%d disks,\nB: Top-1 disk, Y: previous disk',nnz(mat.covered),H*W,vistop))
subplot(223); imshow(mat.axis); title('A-MAT axes')
subplot(224); imshow(mat.radius,[]); title('A-MAT radii')
drawnow;
end

% -------------------------------------------------------------------------
function visualize(mat)
% -------------------------------------------------------------------------
figure; clf;
subplot(221); imshow(mat.axis);             title('Medial axes');
subplot(222); imshow(mat.radius,[]);        title('Radii');
subplot(223); imshow(mat.input);            title('Original image');
subplot(224); imshow(mat.reconstruction);   title('Reconstructed image');
end

end


% -------------------------------------------------------------------------
function [cost, numDisksCovered] = reconstructionCost(img,enc,filters,scales)
% -------------------------------------------------------------------------
% img: HxWxC input image (in the Lab color space). 
% enc: HxWxCxR appearance encodings for all r-disks (mean RGB values by default).
% filters: disk-shaped filters.
% 
% This function computes a heuristic that represents the ability to
% reconstruct a disk-shaped part of the input image, using the mean RGB
% values computed over the same area. Intuitively, the idea behind this
% heuristic is the following: 
% In order to accurately reconstruct an image disk of radius r, using its
% mean RGB values, we must also be able to reconstruct *every* fully
% contained disk of radius r' < r (uniformity criterion).
% 
% Terminology: an r-disk is a disk of radius = r.


[H,W,C] = size(img); R = numel(scales);

% Precompute sums of I.^2 and I within r-disks for all r (needed later).
img2 = img.^2; enc2 = enc.^2;
sumI2 = zeros(H,W,C,R);
for c=1:C
    for r=1:R
        sumI2(:,:,c,r) = conv2(img2(:,:,c),filters{r}/nnz(filters{r}),'same');
    end
end


% Create grid of relative positions of disk centers for all scales. 
Rmax = scales(end); [x,y] = meshgrid(-Rmax:Rmax,-Rmax:Rmax);

% cd is a HxWxR logical array, composed of 2D binary masks. 
% cd(i,j,k) is true iff a "scales(end-1+k)-disk", centered at (i,j)
% is *fully contained* within a "scales(end-1+n)-disk", centered at (0,0),
% where n > k.
% In other words, each nonzero point in cd(:,:,k+1:end) corresponds to a
% different disk, contained in the disk represented by the binary mask in
% cd(:,:,k).
% TODO: Should I add the scales from scales(1):-1:0 too?
cd = bsxfun(@le, x.^2+y.^2, reshape([scales(end-1:-1:1) scales(1)-1].^2, 1,1,[]));

% Accumulate the mean squared errors of all contained r-disks.
cost = zeros(H,W,C,R);
numDisksCovered = zeros(H,W,R);
for r=1:R
    cdsubset = cd(:,:,end-r+1:end);
    % for a given r-disk, consider all contained disks and accumulate
    for i=1:size(cdsubset,3)
        D = cdsubset(:,:,i); D = double(cropImageBox(D,mask2bbox(D)));
        for c=1:C
            cost(:,:,c,r) = cost(:,:,c,r) + ...
                conv2(sumI2(:,:,c,i),  D,'same') + enc2(:,:,c,r)*nnz(D) - ...
                conv2(enc(:,:,c,i), D,'same') .* enc(:,:,c,r) .* 2;
        end
        numDisksCovered(:,:,r) = numDisksCovered(:,:,r) + nnz(D);
    end
    % Fix boundary conditions
    cost([1:r, end-r+1:end],:,:,r) = inf;
    cost(:,[1:r, end-r+1:end],:,r) = inf;
end
cost = max(0,cost); % account for numerical errors (costs should always be positive)

% Combine costs from different channels
if C > 1
    wc = [0.5,0.25,0.25]; % weights for luminance and color channels
    cost = cost(:,:,1,:)*wc(1) + cost(:,:,2,:)*wc(2) + cost(:,:,3,:)*wc(3);
    cost = squeeze(cost);                 
end
end
