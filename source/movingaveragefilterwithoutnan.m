function result = movingaveragefilterwithoutnan (data, number)
    result = NaN(size(data));
    
    lookdifference = floor((number-1)/2);

    for i=max([lookdifference+1 1]):numel(data)-max([lookdifference 0])
        result(i) = nanmean(data(i-lookdifference:i+lookdifference));
        %{
        %ensuring that the result for the current frame doesn't become NaN just because there is one NaN value somewhere in the values that need to be averaged
        toaveragewithoutnan = data(i-lookdifference:i+lookdifference);
        whichindicesareok = ~isnan(toaveragewithoutnan);
        if any(whichindicesareok) %making sure that division by zero warnings are not spammed just because we're attempting to take the mean of an empty matrix
            tempresult(i) = mean(toaveragewithoutnan(whichindicesareok));
        else
            tempresult(i) = NaN;
        end
        %}
    end

end