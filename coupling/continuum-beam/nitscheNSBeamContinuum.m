% This file implements the Nitsche method to join two mechanical models:
% a 2D continuum model and a Timoshenko beam model.
%
% Discretisation: standard Lagrange finite elements.
%
% Problem: Timoshenko beam in bending.
%
% Vinh Phu Nguyen
% Cardiff University, UK
% 3 June 2013

addpath ../../fem_util/
addpath ../../gmshFiles/
addpath ../../post-processing/
addpath ../../fem-functions/
addpath ../../analytical-solutions/


clear all
colordef white
state = 0;
tic;

opts = struct('Color','rgb','Bounds','tight','FontMode','fixed','FontSize',20);
%exportfig(gcf,'splinecurve.eps',opts)


% MATERIAL PROPERTIES
E0  = 3e7;  % Young?s modulus
nu0 = 0.3;  % Poisson?s ratio

% BEAM PROPERTIES
L  = 48;     % length of the beam
c  = 6;      % the distance of the outer fiber of the beam from the mid-line

t  = 2*c; % thickness, area = bxt
b  = 1; %
I0=2*c^3/3;  % the second polar moment of inertia of the beam cross-section.
q  = 0; % uniformly distributed loads
P  = -1000*t^3/12/I0; % end force
G  = E0/2/(1+nu0);
k  = E0*I0;
shearFactor = 5/6;

plotMesh  = 1;

stressState = 'PLANE_STRESS';
% COMPUTE ELASTICITY MATRIX
C = elasticityMatrix(E0,nu0,stressState);

noGPs = 2;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% GENERATE FINITE ELEMENT MESH
%

disp([num2str(toc),'   GENERATING MESH'])

% MESH PROPERTIES

elemType  = 'Q4'; % the element type used in the FEM simulation;
elemTypeB = 'L2'; % the element type used in the FEM simulation;

% domain 1
numx1     = 80;
numy1     = 10;

L1 = 20;
% meshing for domain1
nnx=numx1+1;
nny=numy1+1;
node1=square_node_array([0 -c],[L1 -c],[L1 c],[0 c],nnx,nny);
inc_u=1;
inc_v=nnx;
node_pattern=[ 1 2 nnx+2 nnx+1 ];
element1 =make_elem(node_pattern,numx1,numy1,inc_u,inc_v);

% domain 2

numnode = 30;
node2 = zeros(numnode,2);
node2(:,1) = linspace(L1,L,numnode);

element2  = zeros(numnode-1,2);

for i=1:numnode-1
    element2(i,:) = i:i+1;
end


% PLOT MESH
if ( plotMesh )
    clf
    plot_mesh(node1,element1,elemType,'g.-',2.4);
    plot_mesh(node2,element2,elemTypeB,'r.-',1.7);
    hold on
    axis off
    axis([0 L -c c])
end

% boundary mesh for domain 1
bndMesh1 = [];
for i=1:numy1
    bndMesh1 = [bndMesh1; numx1*i ];
end

% boundary edges

bndNodes  = find(abs(node1(:,1)-L1)<1e-14);
bndEdge1  = zeros(numy1,2);

for i=1:numy1
    bndEdge1(i,:) = bndNodes(i:i+1);
end


[W1,Q1]=quadrature( 2, 'GAUSS', 1 ); % two point quadrature

GP1 = [];
GP2 = [];

for e=1:numy1
    sctrEdge=bndEdge1(e,:);
    sctr1    = element1(bndMesh1(e),:);
    pts1     = node1(sctr1,:);
    for q=1:size(W1)
        pt=Q1(q,:);
        wt=W1(q);
        [N,dNdxi]=lagrange_basis('L2',pt);  % element shape functions
        J0=dNdxi'*node1(sctrEdge,:);
        detJ0=norm(J0);
        J0 = J0/detJ0;
        
        x=N'*node1(sctrEdge,:);
        X1 = global2LocalMap(x,pts1,elemType);
        GP1 = [GP1;X1 wt*detJ0 -J0(2) J0(1)];
        GP2 = [GP2;-1 x(2)];
    end
end

% DEFINE BOUNDARIES

edgeElemType='L2';

% GET NODES ON DISPLACEMENT BOUNDARY
%      Here we get the nodes on the essential boundaries

fixedNode = find(node1(:,1)==0);
rightNode = find(node2(:,1)==L);
midNode1  = find(node1(:,2)==0);

uFixed=zeros(1,length(fixedNode))';  % a vector of u_x for the nodes
vFixed=zeros(1,length(fixedNode))';

for i=1:length(fixedNode)
    inode = fixedNode(i);
    pts   = node1(inode,:);
    ux    = 1000*pts(2)/(6*E0*I0)*(2+nu0)*(pts(2)^2-c^2);
    uy    = -1000/(2*E0*I0)*nu0*pts(2)^2*L;
    uFixed(i)=ux;
    vFixed(i)=uy;
end

numdofs = size(node1,1) + size(node2,1);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% DEFINE SYSTEM DATA STRUCTURES

disp([num2str(toc),' INITIALIZING DATA STRUCTURES'])

f=zeros(2*numdofs,1);          % external load vector
K=zeros(2*numdofs,2*numdofs); % stiffness matrix

% ******************************************************************************
% ***                          P R O C E S S I N G                           ***
% ******************************************************************************
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%% COMPUTE STIFFNESS MATRIX %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
disp([num2str(toc),'   COMPUTING STIFFNESS MATRIX'])

[W,Q]=quadrature( 2, 'GAUSS', 2 ); % 2x2 Gaussian quadrature

% for domain 1

for e=1:size(element1,1)                          % start of element loop
    sctr = element1(e,:);           % element scatter vector
    nn   = length(sctr);
    sctrB(1:2:2*nn) = 2*sctr-1;
    sctrB(2:2:2*nn) = 2*sctr-0;
    
    for q=1:size(W,1)
        pt=Q(q,:);
        wt=W(q);
        [N,dNdxi]=lagrange_basis(elemType,pt); % element shape functions
        J0=node1(sctr,:)'*dNdxi;                % element Jacobian matrix
        invJ0=inv(J0);
        dNdx=dNdxi*invJ0;
        
        B(1,1:2:2*nn)  = dNdx(:,1)';
        B(2,2:2:2*nn)  = dNdx(:,2)';
        B(3,1:2:2*nn)  = dNdx(:,2)';
        B(3,2:2:2*nn)  = dNdx(:,1)';
        
        % COMPUTE ELEMENT STIFFNESS AT QUADRATURE POINT
        K(sctrB,sctrB)=K(sctrB,sctrB)+B'*C*B*W(q)*det(J0);
    end  % of quadrature loop
end

% for domain 2 (beam)
clear sctrB;

[W,Q]=quadrature(  noGPs, 'GAUSS', 1 ); % 2 point quadrature

for e=1:size(element2,1)
    conn  = element2(e,:);
    noFns = length(conn);
    conng = conn + size(node1,1);
    sctrB(1:2:2*noFns) = 2*conng-1;
    sctrB(2:2:2*noFns) = 2*conng-0;
    pts   = node2(conn,:);
    
    % loop over Gauss points
    for gp=1:size(W,1)
        pt      = Q(gp,:);
        wt      = W(gp);
        [N,dNdxi]=lagrange_basis(elemTypeB,pt);  % element shape functions
        J0=dNdxi'*pts;
        detJ0=norm(J0);
        dNdx   = (1/detJ0)*dNdxi;
        
        Bb(2:2:noFns*2)   = dNdx;
        Bs(1:2:noFns*2)   = dNdx;
        Bs(2:2:noFns*2)   = -N;
        
        % compute elementary stiffness matrix
        K(sctrB,sctrB) = K(sctrB,sctrB) + ...
            (k * Bb' * Bb + shearFactor*G*b*t*Bs'*Bs)* detJ0 * wt;
    end
end

% interface integrals

Cbeam  = [E0 0;0 shearFactor*G];
Csolid = C([1 3],:);

for i=1:numy1                     % start of element loop
    e1     = bndMesh1(i);
    sctr1  = element1(e1,:);
    sctr2  = element2(1,:);
    sctr2n = sctr2 + size(node1,1);
    nn1    = length(sctr1);
    nn2    = length(sctr2);
    sctrB1(1:2:2*nn1) = 2*sctr1-1;
    sctrB1(2:2:2*nn1) = 2*sctr1-0;
    sctrB2(1:2:2*nn2) = 2*sctr2n-1;
    sctrB2(2:2:2*nn2) = 2*sctr2n-0;
    
    pts1 = node1(sctr1,:);
    pts2 = node2(sctr2,:);
    
    Kp11 = zeros(nn1*2,nn1*2);
    Kp12 = zeros(nn1*2,nn2*2);
    Kp22 = zeros(nn2*2,nn2*2);
    
    Kd11 = zeros(nn1*2,nn1*2);
    Kd12 = zeros(nn1*2,nn2*2);
    Kd21 = zeros(nn2*2,nn1*2);
    Kd22 = zeros(nn2*2,nn2*2);
    
    for q=2*i-1:2*i
        pt1=GP1(q,1:2);
        wt1=GP1(q,3);
        pt2=GP2(q,1);
        y  =GP2(q,2);
        normal=GP1(q,4:5);
        n = [normal(1) normal(2);0 normal(1)];
        n=-n;
        [N1,dN1dxi]=lagrange_basis(elemType,pt1);
        [N2,dN2dxi]=lagrange_basis(elemTypeB,pt2);
        
        J1 = pts1'*dN1dxi;
        J2 = pts2'*dN2dxi;
        detJ0=norm(J2);
        
        dN1dx   = dN1dxi*inv(J1);
        dN2dx   = (1/detJ0)*dN2dxi;
        
        B1(1,1:2:2*nn1)  = dN1dx(:,1)';
        B1(2,2:2:2*nn1)  = dN1dx(:,2)';
        B1(3,1:2:2*nn1)  = dN1dx(:,2)';
        B1(3,2:2:2*nn1)  = dN1dx(:,1)';
        
        B2(1,2:2:2*nn2)  = -y*dN2dx(:,1)';
        B2(2,1:2:2*nn2)  = dN2dx(:,1)';
        B2(2,2:2:2*nn2)  = -N2;
        
        Nm1(1,1:2:2*nn1)  = N1';
        Nm1(2,2:2:2*nn1)  = N1';
        
        Nm2(1,2:2:2*nn2)  = -y*N2';
        Nm2(2,1:2:2*nn2)  = N2';
        
        % COMPUTE ELEMENT STIFFNESS AT QUADRATURE POINT
                
        Kd11 = Kd11 + 0.5 * Nm1'* n * Csolid * B1 *wt1;
        Kd12 = Kd12 + 0.5 * Nm1'* n * Cbeam  * B2 *wt1;
        Kd21 = Kd21 + 0.5 * Nm2'* n * Csolid * B1 *wt1;
        Kd22 = Kd22 + 0.5 * Nm2'* n * Cbeam  * B2 *wt1;
        
    end  % of quadrature loop
    
    K(sctrB1,sctrB1)  = K(sctrB1,sctrB1)  - Kd11 + Kd11';
    K(sctrB1,sctrB2)  = K(sctrB1,sctrB2)  - Kd12 - Kd21';
    K(sctrB2,sctrB1)  = K(sctrB2,sctrB1)  + Kd21 + Kd12';
    K(sctrB2,sctrB2)  = K(sctrB2,sctrB2)  + Kd22 - Kd22';
end


f(2*numdofs-1) = P;



%%%%%%%%%%%%%%%%%%% END OF STIFFNESS MATRIX COMPUTATION %%%%%%%%%%%%%%%%%%%


% APPLY ESSENTIAL BOUNDARY CONDITIONS
disp([num2str(toc),'   APPLYING BOUNDARY CONDITIONS'])
bcwt=mean(diag(K)); % a measure of the average size of an element in K
% used to keep the conditioning of the K matrix
udofs=2*fixedNode-1;           % global indecies of the fixed x displacements
vdofs=2*fixedNode;   % global indecies of the fixed y displacements
f=f-K(:,udofs)*uFixed;  % modify the force vector
f=f-K(:,vdofs)*vFixed;
K(udofs,:)=0;
K(vdofs,:)=0;
K(:,udofs)=0;
K(:,vdofs)=0;
K(udofs,udofs)=bcwt*speye(length(udofs)); % put ones*bcwt on the diagonal
K(vdofs,vdofs)=bcwt*speye(length(vdofs));
f(udofs)=bcwt*speye(length(udofs))*uFixed;
f(vdofs)=bcwt*speye(length(udofs))*vFixed;

% SOLVE SYSTEM
disp([num2str(toc),'   SOLVING SYSTEM'])
U=K\f;

%******************************************************************************
%*** POST - PROCESSING ***
%***************************************************

numnode1 = size(node1,1);
numnode2 = size(node2,1);

Ux = U(1:2:2*numdofs);
Uy = U(2:2:2*numdofs);

Ux1 = Ux(1:numnode1);
Ux2 = Ux(numnode1+1:end);

Uy1 = Uy(1:numnode1);
Uy2 = Uy(numnode1+1:end);

% Here we plot the stresses and displacements of the solution. As with the
% mesh generation section we don?t go into too much detail - use help
% ?function name? to get more details.
disp([num2str(toc),'   POST-PROCESSING'])

scaleFact=3.;
fn=1;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% PLOT DEFORMED DISPLACEMENT PLOT
%Ux = U(xs);
%Uy = U(ys);

colordef black
figure
clf
hold on
%plot_field(node1+scaleFact*[Ux1 Uy1],element1,elemType,Ux1);
%plot_field(node2+scaleFact*[Ux2 Uy2],element2,elemType,Ux2);
plot_mesh(node1+scaleFact*[Ux1 Uy1],element1,elemType,'w.-',1);
plot_mesh(node2+scaleFact*[zeros(numnode2,1) Ux2],element2,elemTypeB,'w.-',1);
%colorbar
axis off
%title('DEFORMED DISPLACEMENT IN Y-DIRECTION')

% Comapre numerical displacement to exact value
[W,Q]=quadrature(  10, 'GAUSS', 1 ); % 2 point quadrature

Uxm1  = U(2*midNode1-1);
Uym1  = U(2*midNode1);


xx = node1(midNode1,1);
u  = Uym1;

xx = [xx; node2(:,1)];
u  = [u;  Ux2];

% for e=1:size(element2,1)
%    conn  = element2(e,:);
%    noFns = length(conn);
%    conng = conn + size(node1,1);
%    sctrx = 2*conng-1;
%    sctry = 2*conng-0;
%    pts   = node2(conn,:);
%
%    % loop over Gauss points
%     for gp=1:size(W,1)
%       pt      = Q(gp,:);
%       wt      = W(gp);
%       [N,dNdxi]=lagrange_basis(elemTypeB,pt);  % element shape functions
%       J0=dNdxi'*pts;
%       xx = [xx; N'*pts(:,1)];
%       u  = [u;  N'*U(sctrx)];
%     end
% end

% y = 0;
% x = L;
% D = 2*c;
% uyExact = -P/(3*E0*I0)*(L^3);
%
% Ux2(end)
% uyExact
% xx=[node2(:,1)];
% u=[Ux2];


% exact solution u =
y= 0;
x      = linspace(0,L,200);
D=t;
uExact = -1000/6/E0/I0*(3*nu0*y*y*(L-x)+(4+5*nu0)*D*D*x/4+(3*L-x).*x.^2);

% solution from 2D continuum elements

colordef white
figure,set (gcf,'Color','w')
set(gca,'FontSize',14)
hold on
plot(x,uExact,'k-','LineWidth',1.4);
plot(xx,u,'o','MarkerEdgeColor','k',...
    'MarkerFaceColor','g',...
    'MarkerSize',6.5);
% plot(uCont(:,1),uCont(:,2),'b--','LineWidth',1.4);
% plot(uCoup(:,1),uCoup(:,2),'cy.-','LineWidth',1.4);
h=legend('exact','coupling');
xlabel('x')
ylabel('w')
grid on
%axis([0 5 -0.55 0])

%%

elems = numx1*5+1:numx1*6;

sigma   = zeros(length(elems),2);
sigmaRef = zeros(length(elems),2);
xcoord     = zeros(length(elems),2);

for e=1:length(elems)
    ie = elems(e);
    sctr=element1(ie,:);
    nn   = length(sctr);
    sctrB(1:2:2*nn) = 2*sctr-1;
    sctrB(2:2:2*nn) = 2*sctr-0;
    nn=length(sctr);
    
    pt=[0 0];
    [N,dNdxi]=lagrange_basis(elemType,pt);
    J0=node1(sctr,:)'*dNdxi;
    invJ0=inv(J0);
    dNdx=dNdxi*invJ0;
    yPt=N'*node1(sctr,:);
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % COMPUTE B MATRIX
    B(1,1:2:2*nn)  = dNdx(:,1)';
    B(2,2:2:2*nn)  = dNdx(:,2)';
    B(3,1:2:2*nn)  = dNdx(:,2)';
    B(3,2:2:2*nn)  = dNdx(:,1)';
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % COMPUTE ELEMENT STRAIN AND STRESS AT STRESS POINT
    strain=B*U(sctrB);
    stress=C*strain;
    sigma(e,1)    = stress(1);
    sigma(e,2)    = stress(3);
    sigmaRef(e,1) = 1000/I0*(L-yPt(1))*yPt(2);
    sigmaRef(e,2) = -1000/2/I0*(t^2/4-yPt(2)^2);
    xcoord(e,:)     = yPt;
end   % of element loop

colordef white
figure,set (gcf,'Color','w')
set(gca,'FontSize',14)
hold on
plot(xcoord(:,1),sigmaRef(:,1),'k-','LineWidth',1.4);
plot(xcoord(:,1),sigma(:,1),'o','MarkerEdgeColor','k',...
    'MarkerFaceColor','g',...
    'MarkerSize',6.5);
plot(xcoord(:,1),sigmaRef(:,2),'k-','LineWidth',1.4);
plot(xcoord(:,1),sigma(:,2),'s','MarkerEdgeColor','k',...
    'MarkerFaceColor','g',...
    'MarkerSize',6.5);
h=legend('sigmaxx-exact','sigmaxx-coupling','sigmaxy-exact','sigmaxy-coupling');
xlabel('x')
ylabel('stresses at y=0.6')
grid on
%axis([0 5 -0.55 0])



%%

stress=zeros(size(element1,1),size(element1,2),3);

stressPoints=[-1 -1;1 -1;1 1;-1 1];


for e=1:size(element1,1)
    sctr=element1(e,:);
    sctrB(1:2:2*nn) = 2*sctr-1;
    sctrB(2:2:2*nn) = 2*sctr-0;
    nn=length(sctr);
    Ce=C;
    
    for q=1:nn
        pt=stressPoints(q,:);
        [N,dNdxi]=lagrange_basis(elemType,pt);
        J0=node1(sctr,:)'*dNdxi;
        invJ0=inv(J0);
        dNdx=dNdxi*invJ0;
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % COMPUTE B MATRIX
        B(1,1:2:2*nn)  = dNdx(:,1)';
        B(2,2:2:2*nn)  = dNdx(:,2)';
        B(3,1:2:2*nn)  = dNdx(:,2)';
        B(3,2:2:2*nn)  = dNdx(:,1)';
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % COMPUTE ELEMENT STRAIN AND STRESS AT STRESS POINT
        strain=B*U(sctrB);
        stress(e,q,:)=Ce*strain;
    end
end   % of element loop


% sigmaXX = zeros(size(node1,1),2);
% sigmaYY = zeros(size(node1,1),2);
% sigmaXY = zeros(size(node1,1),2);
%
% for e=1:size(element1,1)
%     connect = element1(e,:);
%     for in=1:4
%         nid = connect(in);
%         sigmaXX(nid,:) = sigmaXX(nid,:) + [stress(e,in,1) 1];
%         sigmaYY(nid,:) = sigmaYY(nid,:) + [stress(e,in,2) 1];
%         sigmaXY(nid,:) = sigmaXY(nid,:) + [stress(e,in,3) 1];
%     end
% end
%
% % Average nodal stress values (learned from Mathiew Pais XFEM code)
% sigmaXX(:,1) = sigmaXX(:,1)./sigmaXX(:,2); sigmaXX(:,2) = [];
% sigmaYY(:,1) = sigmaYY(:,1)./sigmaYY(:,2); sigmaYY(:,2) = [];
% sigmaXY(:,1) = sigmaXY(:,1)./sigmaXY(:,2); sigmaXY(:,2) = [];
%
% plotStress(sigmaXX,sigmaXY,sigmaYY,element1,node1);

stressComp=1;
figure
clf
plot_field(node1+scaleFact*[Ux1 Uy1],element1,elemType,stress(:,:,stressComp));
plot_mesh(node2+scaleFact*[zeros(numnode2,1) Ux2],element2,elemTypeB,'b-',2);
%plot_mesh(node2+scaleFact*[Ux2 Uy2],element2,elemType,'r.-',1);
hold on
%plot_mesh(node+scaleFact*[U(xs) U(ys)],element,elemType,'g.-');
%plot_mesh(node,element,elemType,'w--');
colorbar

%%
