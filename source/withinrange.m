function matrixwhere = withinrange (ysize, xsize, xorigin, yorigin, radius, varargin)

    persistent oldmeshx oldmeshy oldysize oldxsize oldxorigin oldyorigin oldradius oldmatrixwhere oldstoredn
    
    if nargin >= 6
        oldresultstokeep = varargin{1};
    else
        oldresultstokeep = 4; %the default of 4 corresponds to 2 different positions on different channels, times 2 different radii for the foreground and the background
    end
    
    if ~exist('oldstoredn', 'var') || isempty(oldstoredn)
        oldstoredn = 0;
    end
    
    if oldstoredn > 0
        for i=1:oldstoredn
            if ysize == oldysize(i) && xsize == oldxsize(i) && xorigin == oldxorigin(i) && yorigin == oldyorigin(i) && radius == oldradius(i)
                matrixwhere = oldmatrixwhere{i};
                return
            end
        end
    end
    
    %the mesh may match previously calculated ones even if the results did not
    foundamatch = false;
    if oldstoredn > 0
        for i=1:oldstoredn
            if all(size(oldmeshx{i}) == [ysize, xsize])
                meshx = oldmeshx{i};
                meshy = oldmeshy{i};
                foundamatch = true;
                break
            end
        end
    end
    if ~foundamatch
        [meshx, meshy] = meshgrid(1:xsize, 1:ysize);
    end
    
    xfrom = max([floor(xorigin - radius), 1]);
    xuntil = min([ceil(xorigin + radius), xsize]);
    yfrom = max([floor(yorigin - radius), 1]);
    yuntil = min([ceil(yorigin + radius), ysize]);
    
    smallwithinmatrix = hypot(meshy(yfrom:yuntil, xfrom:xuntil)-yorigin, meshx(yfrom:yuntil, xfrom:xuntil)-xorigin) <= radius;
    
    matrixwhere = false(ysize, xsize);
    
    matrixwhere(yfrom:yuntil, xfrom:xuntil) = smallwithinmatrix;
    
    oldstoredn = oldstoredn + 1;
    oldysize(oldstoredn) = ysize;
    oldxsize(oldstoredn) = xsize;
    oldxorigin(oldstoredn) = xorigin;
    oldyorigin(oldstoredn) = yorigin;
    oldradius(oldstoredn) = radius;
    oldmatrixwhere{oldstoredn} = matrixwhere;
    oldmeshx{oldstoredn} = meshx;
    oldmeshy{oldstoredn} = meshy;
    
    if oldstoredn > oldresultstokeep
        toremove = oldstoredn - oldresultstokeep;
        
        oldysize(1:toremove) = [];
        oldxsize(1:toremove) = [];
        oldxorigin(1:toremove) = [];
        oldyorigin(1:toremove) = [];
        oldradius(1:toremove) = [];
        oldmatrixwhere(1:toremove) = [];
        oldmeshx(1:toremove) = [];
        oldmeshy(1:toremove) = [];
        
        oldstoredn = oldresultstokeep;
    end

end