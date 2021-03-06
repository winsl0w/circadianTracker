function out=circadianHandData(centroidData,numFlies,centers)

    out=[];
    bins=linspace(0,50,200);

for j=1:numFlies
    inx=centroidData(:,2*j);
    iny=centroidData(:,2*j+1);
    
    out(j).r=single(sqrt((inx-centers(j,1)).^2+(iny-centers(j,2)).^2));
    out(j).theta=single(atan2(iny-centers(j,2),inx-centers(j,1)));
    out(j).direction=single(zeros(size(inx,1),1));
    out(j).speed=single(zeros(size(inx,1),1));
    out(j).direction(2:end)=single(atan2(diff(iny),diff(inx)));
    out(j).speed(2:end)=single(sqrt(diff(iny).^2+diff(inx).^2));
    out(j).speed(out(j).speed>12)=NaN;
    %out(j).width=single(mean(out(j).r)+std(out(j).r)*2.5*2);
    dhist=histc(out(j).r,bins);
    dhist=dhist./sum(dhist);
    dhistCDF=cumsum(dhist);
    [v,i]=min(abs(0.95-dhistCDF));
    out(j).width=bins(i);
end