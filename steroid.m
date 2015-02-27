function [V,d,lambdas,e,tail]=steroid(A,varargin)
% [V,d,lambdas,e,tail]=steroid(A,method) or [V,tail]=steroid(A,method)
% --------------------------------------------------------------------
% Symmetric Tensor Eigen Rank-One Iterative Decomposition. Decomposes a
% symmetric tensor into a real linear combination of real rank-1 symmetric 
% tensors. If STEROID is called with only two output arguments, then only
% the V vectors and the symmetric tail will be computed and returned.
%
% V         =   matrix, each column corresponds with a vector that
%               determines 1 rank-1 symmetric tensor,
%
% d         =   vector, contains the weights of each of the terms defined
%               by the columns of V in the decomposition,
%
% lambdas   =   vector, contains the weights in the STEROID,
%
% e         =   scalar, residual that is not described by the span of V,
%
% tail      =   tensor, symmetric tensor built up from the cross-product
%               contributions in the STEROID,
%
% A         =   tensor, symmetric d-way tensor,
%
% method    =   string, optional: determines how the least-squares problem 
%               W*d=vec(A) will be solved. Possible choices are:
%
%               'bigW': constructs the W matrix with n^d rows, only
%               feasible for small n and d. This is the default option,
%
%               'WtW': solves the much smaller W^T*W*d=W^T*vec(A) problem
%               at the cost of a worse condition number,
%
%               'Wsym': solves the smaller S*W*d=S*vec(A), where S is a row
%               selection matrix that selects only the nchoosek(d+n-1,n-1)
%               distinct entries in A.
%
% Reference
% ---------
%
% Symmetric Tensor Decomposition by an Iterative Eigendecomposition
% Algorithm
%
% 2014, 2015, Kim Batselier & Ngai Wong

n=size(A,1);
d=length(size(A));
doriginal=d;
a=A(:);

if sum(n(1)==size(A)) ~= d
	error('A needs to be a cubical tensor.');
end

numberoflevels=ceil(log2(d));
r=zeros(1,numberoflevels);
dtemp=d;
for i=1:length(r)
    if mod(dtemp,2)==0
        dtemp=dtemp/2;        
    else
        dtemp=(dtemp+1)/2;
    end
    r(i)=n^(dtemp); % number of branches per cluster at level i
end

eigsperlevel=ones(1,numberoflevels);
totaleigs=0;
for i=1:length(r)-1
    eigsperlevel(i+1)=prod(r(1:i));
    totaleigs=totaleigs+eigsperlevel(i+1); 
end
nleaf=prod(r);

Vt=cell(1,totaleigs);
Dt=cell(1,totaleigs);
L=cell(1,totaleigs);

if mod(d,2)==1
    % odd-order, need to embed
    A=embed(A);
    d=(d+1)/2;
else
    d=d/2;
end

% first eig
[V1,D1]=eig(reshape(A,[n^d n^d]));
Dt{1}=diag(D1);
Vt{1}=V1;
% [Dt{1} I]=sort(abs(diag(D1)),'descend');
% Vt{1}=V1(:,I);
L{1}=diag(D1);
counter=2; % this counter keeps track during the iterations which V{i} we are computing. This is a linear counter that counts breadth-first
whichvcounter=1;    % this counter keeps track during the iterations of which V we are computing eigdecomp

if length(r)==1
    V=V1;   
else
    V=zeros(n,prod([sum(abs(Dt{1})>length(Dt{1})*eps(max(Dt{1}))) r(2:end)]));
    vcolcounter=1;
end

for i=1:length(r)-1           % outer loop over the levels
	tol=n^d*eps(max(abs(Dt{whichvcounter})));
% 	tol=n^(d/(2^i))*eps(max(abs(Dt{whichvcounter})));    
    for j=1:prod(r(1:i))      % inner loop over the number of eigs for this level 
        if rem(j,r(i)) == 0
            col=r(i);
        else
            col=rem(j,r(i));
        end
        if ~isempty(Dt{whichvcounter}) && abs(Dt{whichvcounter}(col)) > tol
            if mod(d,2)==1
                % odd-order, need to embed
                tempV=embed(reshape(Vt{whichvcounter}(:,col),n*ones(1,d)));
                dtemp=(d+1)/2;
            else
                tempV=reshape(Vt{whichvcounter}(:,col),n*ones(1,d));
                dtemp=d/2;
            end
            
            [V1,D1]=eig(reshape(tempV,[n^dtemp n^dtemp]));
            Vt{counter}=V1;
            Dt{counter}=diag(D1);
            L{counter}=diag(D1).^(2^(i));
            if i==length(r)-1
                V(:,(vcolcounter-1)*n+1:vcolcounter*n)=V1;
                vcolcounter=vcolcounter+1;
            end
        else
            L{counter}=zeros(n^dtemp,1);
        end
        counter=counter+1;
        if rem(j,length(Dt{whichvcounter}))==0
%             V{whichvcounter}=[];
            whichvcounter =  whichvcounter+1;
        end
    end
    d=dtemp;
end

% remove zero V vectors
 V(:,sum(V,1)==0)=[];

% compute the lambdas
Llevel=cell(1,length(r));   % cat each level singular values into 1 vector
counter=1;
for i=1:length(r),
    for j=1:eigsperlevel(i),
        Llevel{i}=[Llevel{i}; L{counter}];
        counter=counter+1;
    end
end

for i=1:length(r),             % make all singular value vectors the same size (number of leaves)
    Llevel{i}=kron(Llevel{i}, ones(nleaf/length(Llevel{i}),1));
end

lambdas=ones(nleaf,1);         % output singular values at each leaf
for i=1:length(r),
    lambdas=lambdas.*Llevel{i};
end
lambdas(lambdas==0)=[];

clear A D1 V1 Dt Vt L Llevel col colcounter
   
if isempty(varargin)
    method='bigW';
else
    method=varargin{1};
end

if nargout==2
    % only V vectors and tail are required
    % need to compute the tail
    switch lower(method)
        case {'bigw'}
             W=zeros(n^doriginal,size(V,2));
             for i=1:size(W,2)
                 W(:,i)=mkron(V(:,i),doriginal);
             end
             d=reshape(a-W*lambdas,n*ones(1,doriginal));  % compute symmetric tail
        case {'wtw','wsym'}
            % compute symmetric tail
            head=zeros(n^doriginal,1);
            for i=1:length(lambdas)
                head=head+lambdas(i)*mkron(V(:,i),doriginal);
            end
            d=reshape(a-head,n*ones(1,doriginal));
    end
    return
end
    
            
    
%% solve the linear system W*d=vec(A)
switch lower(method)
    case {'bigw'}
        % original LS problem, no symmetry exploited
        W=zeros(n^doriginal,size(V,2));
        for i=1:size(W,2)
            W(:,i)=mkron(V(:,i),doriginal);
        end
        d=W\a;
        I=find(d);
        e=norm(a-W(:,I)*d(I));                          % compute residual
        tail=reshape(a-W*lambdas,n*ones(1,doriginal));  % compute symmetric tail
    case {'wtw',}
        % W^T*W
        WtW=(V'*V).^doriginal;
        % update righ-hand-side of LS problem, X^T*vec(A)
        b=zeros(size(V,2),1);
        for i=1:size(V,2)
            b(i,1)=mkron(V(:,i),doriginal)'*a;
        end
        d=WtW\b;
%         % solve linear system with SVD
%         [Uw Sw Vw]=svd(WtW);
%         s=diag(Sw);
%         rankW=sum(s>size(WtW,2)*eps(s(1)));        
%         Uw=Uw(:,1:rankW);
%         Sw=Sw(1:rankW,1:rankW);
%         Vw=Vw(:,1:rankW);
%         d=Vw*diag(1./diag(Sw))*Uw'*b;
        
        % compute residual
        ahat=zeros(n^doriginal,1);
        I=find(d);
        for i=1:length(I)
            ahat=ahat+d(I(i))*mkron(V(:,I(i)),doriginal);
        end        
        e=norm(a-ahat);
        
        % compute symmetric tail
        head=zeros(n^doriginal,1);
        for i=1:length(lambdas)
            head=head+lambdas(i)*mkron(V(:,i),doriginal);
        end   
        tail=reshape(a-head,n*ones(1,doriginal));
    case {'wsym'}
        % original Ls problem, symmetry exploited
        mons=getMonBase(doriginal,n);
        lindex=exp2ind(mons);
        b=a(lindex);
        Wsym=zeros(size(mons,1),size(V,2));
        for i=1:size(Wsym,1)
           Wsym(i,:)=prod(V.^(mons(i,:)'*ones(1,size(V,2))),1);
        end
        d=Wsym\b;
        I=find(d);
        e=norm(b-Wsym(:,I)*d(I));                          % compute residual
        
        % compute symmetric tail
        head=zeros(n^doriginal,1);
        for i=1:length(lambdas)
            head=head+lambdas(i)*mkron(V(:,i),doriginal);
        end   
        tail=reshape(a-head,n*ones(1,doriginal));
end
        

end